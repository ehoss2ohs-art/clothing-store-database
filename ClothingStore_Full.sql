-- قاعدة بيانات محل ملابس
-- شغل الملف كله مرة واحدة
-- الملف بيمسح القاعدة القديمة لو موجودة وبيبنيها من الاول

USE master;
GO

IF DB_ID(N'ClothingStore') IS NOT NULL
BEGIN
    ALTER DATABASE ClothingStore SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ClothingStore;
END
GO

CREATE DATABASE ClothingStore COLLATE Arabic_CI_AS;
GO

USE ClothingStore;
GO


-- الجداول --

-- الاقسام
-- القسم الرئيسي مالوش اب والفرعي بيتربط بيه
CREATE TABLE Categories (
    CategoryID       INT IDENTITY(1,1) PRIMARY KEY,
    CategoryName     NVARCHAR(100) NOT NULL,
    ParentCategoryID INT NULL REFERENCES Categories(CategoryID),
    CONSTRAINT UQ_Category UNIQUE (CategoryName, ParentCategoryID)
);

-- القصات زي اوفر سايز وبوكس فيت
CREATE TABLE Fits (
    FitID   INT IDENTITY(1,1) PRIMARY KEY,
    FitName NVARCHAR(50) NOT NULL UNIQUE
);

-- الخامات
CREATE TABLE Materials (
    MaterialID   INT IDENTITY(1,1) PRIMARY KEY,
    MaterialName NVARCHAR(50) NOT NULL UNIQUE
);

-- المنتجات
-- IsPrinted بواحد يعني مطبوع وبصفر يعني ساده
CREATE TABLE Products (
    ProductID   INT IDENTITY(1,1) PRIMARY KEY,
    ProductName NVARCHAR(200) NOT NULL,
    CategoryID  INT NOT NULL REFERENCES Categories(CategoryID),
    FitID       INT NULL REFERENCES Fits(FitID),
    MaterialID  INT NULL REFERENCES Materials(MaterialID),
    IsPrinted   BIT NOT NULL DEFAULT 0,
    SellPrice   DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (SellPrice >= 0),
    CostPrice   DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (CostPrice >= 0),
    IsActive    BIT NOT NULL DEFAULT 1,
    CreatedAt   DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE)
);

-- المقاسات والالوان
-- كل مقاس ولون ليهم كمية لوحدهم
-- ReorderLevel هو الحد اللي لما الكمية توصله يظهر تنبيه
CREATE TABLE ProductVariants (
    VariantID    INT IDENTITY(1,1) PRIMARY KEY,
    ProductID    INT NOT NULL REFERENCES Products(ProductID),
    Size         NVARCHAR(10) NOT NULL,
    Color        NVARCHAR(30) NOT NULL,
    Barcode      NVARCHAR(50) NULL,
    Quantity     INT NOT NULL DEFAULT 0 CHECK (Quantity >= 0),
    ReorderLevel INT NOT NULL DEFAULT 3,
    CONSTRAINT UQ_Variant UNIQUE (ProductID, Size, Color)
);

-- الباركود ميتكررش لكن يقبل فاضي
CREATE UNIQUE INDEX UX_Variants_Barcode ON ProductVariants(Barcode) WHERE Barcode IS NOT NULL;

-- العملاء
CREATE TABLE Customers (
    CustomerID INT IDENTITY(1,1) PRIMARY KEY,
    FullName   NVARCHAR(100) NOT NULL,
    Phone      NVARCHAR(20) NULL UNIQUE,
    Address    NVARCHAR(200) NULL,
    CreatedAt  DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE)
);

-- الموظفين
CREATE TABLE Employees (
    EmployeeID INT IDENTITY(1,1) PRIMARY KEY,
    FullName   NVARCHAR(100) NOT NULL,
    JobTitle   NVARCHAR(50) NULL,
    Phone      NVARCHAR(20) NULL,
    Salary     DECIMAL(10,2) NULL,
    HireDate   DATE NULL,
    IsActive   BIT NOT NULL DEFAULT 1
);

-- الموردين
CREATE TABLE Suppliers (
    SupplierID   INT IDENTITY(1,1) PRIMARY KEY,
    SupplierName NVARCHAR(100) NOT NULL,
    Phone        NVARCHAR(20) NULL,
    Address      NVARCHAR(200) NULL
);

-- فواتير البيع
-- لو العميل فاضي يبقى عميل عادي
CREATE TABLE Sales (
    SaleID        INT IDENTITY(1,1) PRIMARY KEY,
    SaleDate      DATETIME NOT NULL DEFAULT GETDATE(),
    CustomerID    INT NULL REFERENCES Customers(CustomerID),
    EmployeeID    INT NULL REFERENCES Employees(EmployeeID),
    PaymentMethod NVARCHAR(20) NOT NULL DEFAULT N'كاش'
                  CHECK (PaymentMethod IN (N'كاش', N'فيزا', N'محفظة', N'انستاباي', N'آجل')),
    Discount      DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (Discount >= 0),
    Notes         NVARCHAR(200) NULL
);

-- بنود فاتورة البيع
-- بنسجل السعر والتكلفة وقت البيع عشان الربح يفضل صح لو السعر اتغير بعدين
CREATE TABLE SaleItems (
    SaleItemID INT IDENTITY(1,1) PRIMARY KEY,
    SaleID     INT NOT NULL REFERENCES Sales(SaleID) ON DELETE CASCADE,
    VariantID  INT NOT NULL REFERENCES ProductVariants(VariantID),
    Quantity   INT NOT NULL CHECK (Quantity > 0),
    UnitPrice  DECIMAL(10,2) NOT NULL CHECK (UnitPrice >= 0),
    UnitCost   DECIMAL(10,2) NOT NULL DEFAULT 0
);

-- فواتير الشراء من الموردين
CREATE TABLE Purchases (
    PurchaseID   INT IDENTITY(1,1) PRIMARY KEY,
    SupplierID   INT NOT NULL REFERENCES Suppliers(SupplierID),
    PurchaseDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
    Notes        NVARCHAR(200) NULL
);

-- بنود فاتورة الشراء
CREATE TABLE PurchaseItems (
    PurchaseItemID INT IDENTITY(1,1) PRIMARY KEY,
    PurchaseID     INT NOT NULL REFERENCES Purchases(PurchaseID) ON DELETE CASCADE,
    VariantID      INT NOT NULL REFERENCES ProductVariants(VariantID),
    Quantity       INT NOT NULL CHECK (Quantity > 0),
    UnitCost       DECIMAL(10,2) NOT NULL CHECK (UnitCost >= 0)
);
GO


-- التريجرات --
-- بتحدث المخزون لوحدها

-- لما نبيع الكمية تقل
-- ولو الكمية مش كفاية العملية بتتلغي
CREATE TRIGGER trg_SaleItems_Insert ON SaleItems AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    UPDATE v SET v.Quantity = v.Quantity - i.TotalQty
    FROM ProductVariants v
    JOIN (SELECT VariantID, SUM(Quantity) AS TotalQty FROM inserted GROUP BY VariantID) i
      ON i.VariantID = v.VariantID;
END;
GO

-- لو مسحنا بند من فاتورة الكمية ترجع
CREATE TRIGGER trg_SaleItems_Delete ON SaleItems AFTER DELETE AS
BEGIN
    SET NOCOUNT ON;
    UPDATE v SET v.Quantity = v.Quantity + d.TotalQty
    FROM ProductVariants v
    JOIN (SELECT VariantID, SUM(Quantity) AS TotalQty FROM deleted GROUP BY VariantID) d
      ON d.VariantID = v.VariantID;
END;
GO

-- لما نشتري بضاعة الكمية تزيد
CREATE TRIGGER trg_PurchaseItems_Insert ON PurchaseItems AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    UPDATE v SET v.Quantity = v.Quantity + i.TotalQty
    FROM ProductVariants v
    JOIN (SELECT VariantID, SUM(Quantity) AS TotalQty FROM inserted GROUP BY VariantID) i
      ON i.VariantID = v.VariantID;
END;
GO


-- الفيوز --

-- اجمالي كل فاتورة والربح بتاعها
CREATE VIEW vw_SaleTotals AS
SELECT s.SaleID, s.SaleDate, s.CustomerID, s.EmployeeID, s.PaymentMethod,
       SUM(si.Quantity * si.UnitPrice)                              AS Subtotal,
       s.Discount,
       SUM(si.Quantity * si.UnitPrice) - s.Discount                 AS Total,
       SUM(si.Quantity * (si.UnitPrice - si.UnitCost)) - s.Discount AS Profit
FROM Sales s
JOIN SaleItems si ON si.SaleID = s.SaleID
GROUP BY s.SaleID, s.SaleDate, s.CustomerID, s.EmployeeID, s.PaymentMethod, s.Discount;
GO

-- المخزون بالتفصيل
CREATE VIEW vw_Inventory AS
SELECT v.VariantID, p.ProductID, p.ProductName,
       mc.CategoryName AS MainCategory, c.CategoryName AS SubCategory,
       f.FitName, m.MaterialName,
       CASE WHEN p.IsPrinted = 1 THEN N'مطبوع' ELSE N'ساده' END AS PrintType,
       v.Size, v.Color, v.Barcode, v.Quantity, v.ReorderLevel,
       p.SellPrice, p.CostPrice,
       v.Quantity * p.CostPrice AS StockCostValue
FROM ProductVariants v
JOIN Products p         ON p.ProductID = v.ProductID
JOIN Categories c       ON c.CategoryID = p.CategoryID
LEFT JOIN Categories mc ON mc.CategoryID = c.ParentCategoryID
LEFT JOIN Fits f        ON f.FitID = p.FitID
LEFT JOIN Materials m   ON m.MaterialID = p.MaterialID;
GO

-- الحاجات اللي قربت تخلص
CREATE VIEW vw_LowStock AS
SELECT * FROM vw_Inventory WHERE Quantity <= ReorderLevel;
GO


-- البيانات --

-- الاقسام الرئيسية
INSERT INTO Categories (CategoryName)
VALUES (N'هوديز وسويتشيرتات'), (N'بناطيل'), (N'كلاسيك');

-- الاقسام الفرعية
INSERT INTO Categories (CategoryName, ParentCategoryID)
SELECT N'هودي',           CategoryID FROM Categories WHERE CategoryName = N'هوديز وسويتشيرتات' UNION ALL
SELECT N'سويت شيرت',      CategoryID FROM Categories WHERE CategoryName = N'هوديز وسويتشيرتات' UNION ALL
SELECT N'راوند',          CategoryID FROM Categories WHERE CategoryName = N'هوديز وسويتشيرتات' UNION ALL
SELECT N'بنطلون استريتش', CategoryID FROM Categories WHERE CategoryName = N'بناطيل' UNION ALL
SELECT N'جينز',           CategoryID FROM Categories WHERE CategoryName = N'بناطيل' UNION ALL
SELECT N'بنطلون عادي',    CategoryID FROM Categories WHERE CategoryName = N'بناطيل' UNION ALL
SELECT N'قمصان',          CategoryID FROM Categories WHERE CategoryName = N'كلاسيك' UNION ALL
SELECT N'بناطيل كلاسيك',  CategoryID FROM Categories WHERE CategoryName = N'كلاسيك' UNION ALL
SELECT N'جواكت',          CategoryID FROM Categories WHERE CategoryName = N'كلاسيك';

INSERT INTO Fits (FitName)
VALUES (N'أوفر سايز'), (N'بوكس فيت'), (N'وايد ليج'), (N'كارجو'), (N'كلاسيك'), (N'عادي');

INSERT INTO Materials (MaterialName)
VALUES (N'ميلتون استرتش'), (N'قطن'), (N'قطن بلوش'), (N'جينز'), (N'كتان'), (N'جلد'), (N'سوفت'), (N'بامب');

-- المنتجات من دفتر المحل
-- الاسعار صفر لحد ما نحطها
WITH src (ProductName, SubCat, Fit, Material, IsPrinted) AS (
    SELECT * FROM (VALUES
    -- هوديز وسويتشيرتات
    (N'هودي ميلتون استرتش أوفر سايز ساده',    N'هودي',      N'أوفر سايز', N'ميلتون استرتش', 0),
    (N'هودي قطن بلوش مطبوع',                  N'هودي',      NULL,         N'قطن بلوش',      1),
    (N'سويت شيرت دبل سوسته',                  N'سويت شيرت', NULL,         NULL,             0),
    (N'هودي سوسته بوكس فيت قطن',              N'هودي',      N'بوكس فيت',  N'قطن',           0),
    (N'هودي سوسته أوفر سايز ميلتون استرتش',   N'هودي',      N'أوفر سايز', N'ميلتون استرتش', 0),
    (N'هودي سوسته بوكس فيت مطبوع',            N'هودي',      N'بوكس فيت',  NULL,             1),
    (N'هودي سوسته أوفر سايز مطبوع',           N'هودي',      N'أوفر سايز', NULL,             1),
    (N'راوند ساده ميلتون استرتش',             N'راوند',     NULL,         N'ميلتون استرتش', 0),
    (N'راوند مطبوع ميلتون استرتش أوفر سايز',  N'راوند',     N'أوفر سايز', N'ميلتون استرتش', 1),
    -- بناطيل
    (N'بنطلون وايد ليج ميلتون استرتش', N'بنطلون استريتش', N'وايد ليج', N'ميلتون استرتش', 0),
    (N'بنطلون وايد ليج',               N'بنطلون استريتش', N'وايد ليج', NULL,             0),
    (N'بنطلون وايد ليج جيه ميلتون',    N'بنطلون استريتش', N'وايد ليج', N'ميلتون استرتش', 0),
    (N'بنطلون سوفت',                   N'بنطلون استريتش', NULL,        N'سوفت',          0),
    (N'بنطلون وايد ليج جينز',          N'جينز',           N'وايد ليج', N'جينز',          0),
    (N'بنطلون كارجو جينز',             N'جينز',           N'كارجو',    N'جينز',          0),
    (N'بنطلون تلبيس عادي',             N'بنطلون عادي',    N'عادي',     NULL,             0),
    -- كلاسيك
    (N'قميص بوكس فيت مقلم',     N'قمصان',         N'بوكس فيت', NULL,    0),
    (N'قميص كلاسيك أبيض وأسود', N'قمصان',         N'كلاسيك',   NULL,    0),
    (N'قميص مقلم',              N'قمصان',         NULL,        NULL,    0),
    (N'قميص كتان',              N'قمصان',         NULL,        N'كتان', 0),
    (N'بنطلون كلاسيك',          N'بناطيل كلاسيك', N'كلاسيك',   NULL,    0),
    (N'بنطلون وايد ليج كلاسيك', N'بناطيل كلاسيك', N'وايد ليج', NULL,    0),
    (N'جاكت جلد',               N'جواكت',         NULL,        N'جلد',  0),
    (N'جاكت جينز',              N'جواكت',         NULL,        N'جينز', 0),
    (N'جاكت بامب',              N'جواكت',         NULL,        N'بامب', 0),
    (N'جاكت بدل كلاسيك',        N'جواكت',         N'كلاسيك',   NULL,    0)
    ) AS t(ProductName, SubCat, Fit, Material, IsPrinted)
)
INSERT INTO Products (ProductName, CategoryID, FitID, MaterialID, IsPrinted)
SELECT s.ProductName, c.CategoryID, f.FitID, m.MaterialID, s.IsPrinted
FROM src s
JOIN Categories c ON c.CategoryName = s.SubCat AND c.ParentCategoryID IS NOT NULL
LEFT JOIN Fits f ON f.FitName = s.Fit
LEFT JOIN Materials m ON m.MaterialName = s.Material;

-- موظف مبدئي
INSERT INTO Employees (FullName, JobTitle) VALUES (N'صاحب المحل', N'مدير');
GO


-- الاسعار --

-- سعر الجملة هو التكلفة
-- سعر البيع هو الجملة زائد ربح القطعة
DECLARE @Markup DECIMAL(10,2) = 200;

UPDATE p
SET p.CostPrice = x.Cost,
    p.SellPrice = x.Cost + @Markup
FROM Products p
JOIN Categories c ON c.CategoryID = p.CategoryID
JOIN (VALUES
    (N'هودي',           350),
    (N'سويت شيرت',      330),
    (N'راوند',          330),
    (N'بنطلون استريتش', 320),
    (N'بنطلون عادي',    320),
    (N'بناطيل كلاسيك',  320),
    (N'جينز',           370),
    (N'قمصان',          270),
    (N'جواكت',          470)
) x(SubCat, Cost) ON x.SubCat = c.CategoryName;
GO


-- الالوان والمقاسات --

-- جدول مؤقت فيه الالوان بتاعة كل قسم
CREATE TABLE #Rules (
    SubCat      NVARCHAR(100) COLLATE DATABASE_DEFAULT NULL,
    ProductName NVARCHAR(200) COLLATE DATABASE_DEFAULT NULL,
    Color       NVARCHAR(30)  COLLATE DATABASE_DEFAULT NOT NULL
);

-- الهودي والسويت شيرت والراوند والقمصان نفس الالوان
INSERT INTO #Rules (SubCat, Color)
SELECT s.SubCat, c.Color
FROM (VALUES (N'هودي'), (N'سويت شيرت'), (N'راوند'), (N'قمصان')) s(SubCat)
CROSS JOIN (VALUES (N'بيج'), (N'أسود'), (N'أبيض'), (N'بيبي بلو'), (N'بيرجاندي')) c(Color);

-- البنطلون القماش
INSERT INTO #Rules (SubCat, Color)
SELECT s.SubCat, c.Color
FROM (VALUES (N'بنطلون استريتش'), (N'بنطلون عادي'), (N'بناطيل كلاسيك')) s(SubCat)
CROSS JOIN (VALUES (N'بني'), (N'أسود'), (N'رصاصي')) c(Color);

-- الجينز
INSERT INTO #Rules (SubCat, Color)
SELECT N'جينز', c.Color
FROM (VALUES (N'تلجي'), (N'رمادي'), (N'زيتي')) c(Color);

-- الجواكت كل واحد بالوانه
INSERT INTO #Rules (ProductName, Color) VALUES
 (N'جاكت جلد',        N'أسود'), (N'جاكت جلد',  N'بني'),  (N'جاكت جلد', N'جملي'),
 (N'جاكت جينز',       N'أزرق'), (N'جاكت جينز', N'أسود'), (N'جاكت جينز', N'تلجي'),
 (N'جاكت بامب',       N'أسود'), (N'جاكت بامب', N'زيتي'), (N'جاكت بامب', N'بيج'), (N'جاكت بامب', N'كحلي'),
 (N'جاكت بدل كلاسيك', N'أسود'), (N'جاكت بدل كلاسيك', N'كحلي'), (N'جاكت بدل كلاسيك', N'رصاصي');

-- كل منتج في كل لون في المقاسات L و XL و 2XL
INSERT INTO ProductVariants (ProductID, Size, Color, Quantity)
SELECT p.ProductID, sz.Size, r.Color, 0
FROM Products p
JOIN Categories c ON c.CategoryID = p.CategoryID
JOIN #Rules r
  ON r.ProductName = p.ProductName
  OR (r.ProductName IS NULL AND r.SubCat = c.CategoryName)
CROSS JOIN (VALUES (N'L'), (N'XL'), (N'2XL')) sz(Size);

DROP TABLE #Rules;

-- باركود مؤقت لكل مقاس ولون
UPDATE ProductVariants
SET Barcode = N'2000' + RIGHT('000000' + CAST(VariantID AS VARCHAR(10)), 6);
GO


-- الاجراءات --
-- بتسجل البيع والشراء بالباركود وبتحسب السعر والتكلفة لوحدها

-- فاتورة بيع جديدة
-- بترجع رقم الفاتورة عشان نضيف عليها القطع
CREATE OR ALTER PROCEDURE sp_NewSale
    @EmployeeID    INT = 1,
    @PaymentMethod NVARCHAR(20) = N'كاش',
    @Discount      DECIMAL(10,2) = 0,
    @CustomerID    INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Sales (EmployeeID, PaymentMethod, Discount, CustomerID)
    VALUES (@EmployeeID, @PaymentMethod, @Discount, @CustomerID);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS SaleID;
END;
GO

-- اضافة قطعة لفاتورة بيع بالباركود
-- السعر والتكلفة بيتسحبوا من المنتج
-- ولو فيه فصال ابعت السعر في UnitPrice
CREATE OR ALTER PROCEDURE sp_AddSaleItem
    @SaleID    INT,
    @Barcode   NVARCHAR(50),
    @Quantity  INT = 1,
    @UnitPrice DECIMAL(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @VariantID INT, @Price DECIMAL(10,2), @Cost DECIMAL(10,2), @Stock INT;

    IF NOT EXISTS (SELECT 1 FROM Sales WHERE SaleID = @SaleID)
        THROW 50001, N'رقم الفاتورة مش موجود', 1;

    SELECT @VariantID = v.VariantID,
           @Price     = p.SellPrice,
           @Cost      = p.CostPrice,
           @Stock     = v.Quantity
    FROM ProductVariants v
    JOIN Products p ON p.ProductID = v.ProductID
    WHERE v.Barcode = @Barcode;

    IF @VariantID IS NULL
        THROW 50002, N'الباركود ده مش موجود', 1;

    IF @Stock < @Quantity
        THROW 50003, N'الكمية المتاحة في المخزون مش كفاية', 1;

    INSERT INTO SaleItems (SaleID, VariantID, Quantity, UnitPrice, UnitCost)
    VALUES (@SaleID, @VariantID, @Quantity, ISNULL(@UnitPrice, @Price), @Cost);
END;
GO

-- فاتورة شراء جديدة من مورد
CREATE OR ALTER PROCEDURE sp_NewPurchase
    @SupplierID INT,
    @Notes      NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Purchases (SupplierID, Notes)
    VALUES (@SupplierID, @Notes);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS PurchaseID;
END;
GO

-- اضافة بضاعة لفاتورة شراء بالباركود
-- لو مكتبتش التكلفة بتاخد سعر الجملة المسجل
CREATE OR ALTER PROCEDURE sp_AddPurchaseItem
    @PurchaseID INT,
    @Barcode    NVARCHAR(50),
    @Quantity   INT,
    @UnitCost   DECIMAL(10,2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @VariantID INT, @Cost DECIMAL(10,2);

    IF NOT EXISTS (SELECT 1 FROM Purchases WHERE PurchaseID = @PurchaseID)
        THROW 50004, N'رقم فاتورة الشراء مش موجود', 1;

    SELECT @VariantID = v.VariantID, @Cost = p.CostPrice
    FROM ProductVariants v
    JOIN Products p ON p.ProductID = v.ProductID
    WHERE v.Barcode = @Barcode;

    IF @VariantID IS NULL
        THROW 50002, N'الباركود ده مش موجود', 1;

    INSERT INTO PurchaseItems (PurchaseID, VariantID, Quantity, UnitCost)
    VALUES (@PurchaseID, @VariantID, @Quantity, ISNULL(@UnitCost, @Cost));
END;
GO


-- بيانات تجريبية --

-- خليها 1 لو عايز مورد وفاتورة شراء وفاتورة بيع للتجربة
-- وخليها 0 لو هتشتغل على المحل بجد
DECLARE @LoadDemo BIT = 1;

IF @LoadDemo = 1
BEGIN
    INSERT INTO Suppliers (SupplierName) VALUES (N'مورد الجملة');
    DECLARE @SupID INT = SCOPE_IDENTITY();

    -- شراء 10 قطع من كل باركود
    INSERT INTO Purchases (SupplierID, Notes) VALUES (@SupID, N'بضاعة تجريبية');
    DECLARE @PurID INT = SCOPE_IDENTITY();
    EXEC sp_AddPurchaseItem @PurchaseID = @PurID, @Barcode = N'2000000001', @Quantity = 10;
    EXEC sp_AddPurchaseItem @PurchaseID = @PurID, @Barcode = N'2000000002', @Quantity = 10;

    -- بيع قطعتين
    INSERT INTO Sales (EmployeeID) VALUES (1);
    DECLARE @SaleID INT = SCOPE_IDENTITY();
    EXEC sp_AddSaleItem @SaleID = @SaleID, @Barcode = N'2000000001', @Quantity = 2;
END
GO


-- استعلامات بستخدمها --

-- مبيعات وارباح النهاردة
-- SELECT COUNT(*) AS Invoices, SUM(Total) AS Sales, SUM(Profit) AS Profit
-- FROM vw_SaleTotals WHERE CAST(SaleDate AS DATE) = CAST(GETDATE() AS DATE);

-- الحاجات اللي قربت تخلص
-- SELECT ProductName, Size, Color, Quantity FROM vw_LowStock ORDER BY Quantity;

-- اكتر 10 منتجات مبيعا
-- SELECT TOP 10 p.ProductName, SUM(si.Quantity) AS Sold
-- FROM SaleItems si
-- JOIN ProductVariants v ON v.VariantID = si.VariantID
-- JOIN Products p ON p.ProductID = v.ProductID
-- GROUP BY p.ProductName ORDER BY Sold DESC;

-- قيمة المخزون بسعر التكلفة
-- SELECT SUM(StockCostValue) AS StockValue FROM vw_Inventory;

-- تسجيل بيع وشراء بالاجراءات
-- EXEC sp_NewPurchase @SupplierID = 1;
-- EXEC sp_AddPurchaseItem @PurchaseID = 1, @Barcode = N'2000000003', @Quantity = 10;
-- EXEC sp_NewSale;
-- EXEC sp_AddSaleItem @SaleID = 1, @Barcode = N'2000000003', @Quantity = 1;

-- تأكيد ان كله اتعمل
SELECT COUNT(*) AS Products FROM Products;
SELECT COUNT(*) AS Variants FROM ProductVariants;
