/* ============================================================================
   POTRACKER v3 - LIVE SOP / POP / STOCK FOR BOUGHT-IN GOODS   Sage 200 Professional
   Server TIB-SQL-002. Reads both companies - S200_LIVE (Tibard) and
   OliverHarveyLive - in one pass via three-part names, the same way as the
   special makes query. Every column name below was confirmed against the
   live schema (INFORMATION_SCHEMA dump, Sep 2026).

   ONE PASTE. Copy columns A to AD, all rows, without the header. Three row
   types share one column layout and the app splits them on column A:

     SO   one row per live sales order line (product lines only)
     PO   one row per live purchase order line (product lines only)
     STK  one row per stock code per company, for every code that appears on
          an SO or PO row - the classification and the stock figures

   NO CLASSIFICATION IS DONE HERE. Unlike the special makes query, nothing is
   dropped for being stock held or made in house. The STK row carries
   Manufacturer, StockHeld, product group and BOM type, and the app decides.
   That is deliberate: the made-in-house test starts on Manufacturer and will
   move to BOMs later, and that switch must not need a SQL change.

   THE APP'S CALCULATION, per code, per company:

     Need = (SO outstanding - SO allocated) - Free stock - PO outstanding

   Allocated is subtracted because Sage's free stock already excludes it -
   counting an allocated line as demand AND treating its stock as unavailable
   would double up. Netting is PER COMPANY. OH buys direct from suppliers and
   sometimes from Tibard (supplier TIB001): that PO covers the OH line, and
   the mirror Tibard sales order on account OLIVER carries the demand on the
   Tibard side, where it nets against Tibard stock and Tibard POs. Nothing is
   counted twice; the Intercompany flag just shows where the demand came from.

   QUANTITIES ARE IN STOCK UNITS (the StockUnit... columns), not selling
   units, because they are compared with stock. For garments they are equal.

   COLUMN LAYOUT - FIXED. The app parses by position. Blank = not applicable.

     A  RowType         SO / PO / STK
     B  Company         TIBARD / OLIVER HARVEY
     C  RowKey          TIB-SO-<lineid>, OH-PO-<lineid>, TIB-STK-<code> ...
                        company-prefixed: the two databases number their
                        lines independently, so the same ID exists in both
     D  ProductCode
     E  Description     SO/PO: line description. STK: stock item name, or
                        CODE NOT IN STOCK FILE
     F  DocNo           SO: sales order no. PO: purchase order no
     G  LineSeq         print sequence on the order
     H  AccountNo       SO: customer account. PO: supplier account.
                        STK: preferred supplier account
     I  AccountName     as above
     J  Reference       SO: customer's own order ref. PO: supplier's ref.
                        STK: supplier's stock code
     K  DateISO         SO: promised date, ORDER HEADER FIRST (see below).
                        PO: requested delivery date - header, POP has no line date
     L  Qty1            SO/PO: ordered.             STK: confirmed in stock
     M  Qty2            SO: despatched. PO: received. STK: allocated (SOP+stock+BOM)
     N  Qty3            SO/PO: OUTSTANDING.         STK: FREE STOCK (Sage's figure)
     O  Qty4            SO: allocated to this line.  STK: Sage's cached on-PO qty,
                        a cross-check against the PO rows
     P  FulfilMethodID  SO: fulfilment method on the line. STK: the item's default
     Q  LinkID          SO: the first back-to-back PO generated from this order.
                        PO: the sales order this PO was generated from
     R  B2BCount        SO: how many POs this order generated. PO: how many SOs
                        it was generated from. STK: how many back-to-back POs
                        have contained this code in the last 12 months - the
                        "this item is normally ordered back to back" signal
     S  Intercompany    Y on Tibard SO to OLIVER, OH SO to TIB003, OH PO on TIB001
     T  Manufacturer    STK, exactly as typed in Sage. Blank is meaningful
     U  StockHeld       STK: Yes or blank, using the special makes rule
     V  WebsiteOH       STK: Yes when Oliver Harvey AnalysisCode7 = Yes
     W  ProductGroup    STK: product group code (54 = Additional Charges)
     X  BOMItemTypeID   STK: for the later switch to a BOM-based test
     Y  LeadTime        STK: preferred supplier's lead time
     Z  LeadTimeUnitID  STK: unit of Y
     AA MOQ             STK: preferred supplier's minimum order quantity
     AB DocStatusID     SO/PO: order status. 0 = live, 1 = on hold
     AC OrderDate       SO/PO: the order's document date - the date the order
                        was raised in Sage (header DocumentDate, yyyy-mm-dd).
                        Shown as "Ordered" on the app's drill-down. STK: blank
     AD EnteredBy       SO/PO: the Sage user who raised the order (header
                        UserName - the "User" column on the Sales Order List).
                        Shown under the order number on the drill-down. STK: blank

   MANUFACTURER (T) - the app's made-in-house test is an EXACT match after
   trimming, on this list:
     Tibard, Oliver Harvey, Clockwork, Clockwork Clothing, Clockwork Giant Clothing
   Everything else is bought in, INCLUDING 'Premier/Tibard', 'Gildan/Tibard',
   'Stanley/Stella/Oliver Harvey' - bought in and personalised in house. This
   is why the special makes LIKE '%Tibard%' rule is NOT used here. Blank is
   bought in too, but the app flags it so the stock file can be updated: the
   Tibard stock file has 23,249 blanks plus size codes and bin locations typed
   into the field ('2786', 'A1', 'h3 / 104', 'unit h3').

   STOCK HELD (U) is the special makes rule and it differs by company:
     TIBARD          AnalysisCode3 = Yes
     OLIVER HARVEY   AnalysisCode3 = Yes, OR AnalysisCode7 (Website) = Yes,
                     OR the TIBARD record for the same code has AnalysisCode3 = Yes
   Blank and No both mean not stock held.

   PROMISED DATE (K, SO rows): order header first, then the line. Amending an
   order's promised date in Sage updates the header only - lines keep the date
   they were raised with. Learned on the special makes report (order 114816).

   ORDER DATE (AC): the header DocumentDate, which Sage fills with the entry
   date when the order is raised. It is the same column the b2b12 block
   already filters on. If the buyer needs the system timestamp instead of
   the document date, swap DocumentDate for DateTimeCreated in the four
   OrderDate lines below - same format, same position.

   ENTERED BY (AD): SOPOrderReturn.UserName / POPOrderReturn.UserName, the
   Sage login that created the order. This is the "User" column on the Sales
   Order List. Sage 200 has no separate sales-rep field on the SOP header; if
   the business records the rep in an analysis code instead, swap UserName
   for that AnalysisCodeN in the four EnteredBy lines below.

   STATUS FILTERS: DocumentTypeID 0 = order (not return). DocumentStatusID:
   0 = live, 1 = on hold, 2 = complete, 4 = seen once (cancelled or disputed).
   Confirmed on POP Sep 2026: the on-hold PO behind BTTSUC301MM03CHILLI was
   status 1, and 104,512 completed POs were status 2. LIVE AND ON-HOLD orders
   are both returned, status in column AB, so the app shows "PO on hold"
   instead of "needs ordering" and can count held sales demand separately.
   The first cut returned live only and 17 codes wrongly looked unordered.

   BACK TO BACK: Sage links each generated PO to its sales order in
   MMS123BackToBackPO (SOPOrderReturnID <-> POPOrderReturnID; 58,727 links,
   in daily use, Ralawise mostly). That table is the rule behind Q and R.
   The fulfilment method fields (P) are NOT a signal on this system - every
   live line is 0 - and PO source fields are blank on all 105,047 POs. The
   check the buyer needs: an SO line for a code with back-to-back history
   (STK column R > 0) and no linked PO (Q blank). If the Oliver Harvey block
   errors on MMS123BackToBackPO, the table is not in that database - replace
   the three OH subqueries with '' and '0'.

   STOCK FIGURES sum every warehouse the item sits in. If the buyer only
   wants the trading warehouse counted, add a Warehouse filter to the two
   WarehouseItem blocks - the Warehouse table has UseForSalesTrading.
   ========================================================================= */

WITH so AS (

/* ---------------------------------------------------------------- TIBARD -- */
SELECT
    'TIBARD'                                                    AS Company,
    'TIB-SO-' + CAST(sorl.SOPOrderReturnLineID AS varchar(20))  AS RowKey,
    LTRIM(RTRIM(sorl.ItemCode))                                 AS ProductCode,
    /* Tabs and line breaks stripped everywhere - the app splits pasted rows on TAB. */
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(sorl.ItemDescription,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS Description,
    sor.DocumentNo                                              AS DocNo,
    sorl.PrintSequenceNumber                                    AS LineSeq,
    ISNULL(cust.CustomerAccountNumber,'')                       AS AccountNo,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(cust.CustomerAccountName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS AccountName,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(sor.CustomerDocumentNo,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS Reference,
    /* Header before line - see PROMISED DATE above. Text yyyy-mm-dd so the
       browser never has to guess dd/mm against mm/dd. */
    CONVERT(varchar(10), COALESCE(sor.PromisedDeliveryDate,  sorl.PromisedDeliveryDate,
                                  sor.RequestedDeliveryDate, sorl.RequestedDeliveryDate), 23)
                                                                AS DateISO,
    CAST(sorl.StockUnitLineQuantity AS decimal(18,2))           AS Qty1,
    CAST(ISNULL(sorl.StockUnitDespRcptQuantity,0) AS decimal(18,2))
                                                                AS Qty2,
    CAST(sorl.StockUnitLineQuantity - ISNULL(sorl.StockUnitDespRcptQuantity,0) AS decimal(18,2))
                                                                AS Qty3,
    CAST(ISNULL(sorl.StockUnitAllocatedQuantity,0) AS decimal(18,2))
                                                                AS Qty4,
    ISNULL(CAST(sorl.SOPOrderFulfilmentMethodID AS varchar(10)),'')
                                                                AS FulfilMethodID,
    /* Back to back: the PO(s) Sage generated from this order, via
       MMS123BackToBackPO. Q = first linked PO number, R = how many. Blank Q
       on a code the buyer normally orders back to back (STK column R > 0) is
       the miss this app exists to catch. */
    ISNULL((SELECT TOP 1 lpo.DocumentNo
            FROM  S200_LIVE.dbo.MMS123BackToBackPO b
            JOIN  S200_LIVE.dbo.POPOrderReturn lpo ON lpo.POPOrderReturnID = b.POPOrderReturnID
            WHERE b.SOPOrderReturnID = sor.SOPOrderReturnID
            ORDER BY lpo.DocumentNo),'')                        AS LinkID,
    CAST((SELECT COUNT(*) FROM S200_LIVE.dbo.MMS123BackToBackPO b
          WHERE b.SOPOrderReturnID = sor.SOPOrderReturnID) AS varchar(10))
                                                                AS B2BCount,
    /* Matched on ACCOUNT NUMBER, never name - same reason as special makes. */
    CASE WHEN cust.CustomerAccountNumber = 'OLIVER' THEN 'Y' ELSE '' END
                                                                AS Intercompany,
    CAST(sor.DocumentStatusID AS varchar(10))                   AS DocStatusID,
    /* Date the order was raised in Sage - see ORDER DATE above. */
    ISNULL(CONVERT(varchar(10), sor.DocumentDate, 23),'')       AS OrderDate,
    /* Sage user who raised the order - see ENTERED BY above. */
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(sor.UserName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS EnteredBy
FROM        S200_LIVE.dbo.SOPOrderReturn      sor
INNER JOIN  S200_LIVE.dbo.SOPOrderReturnLine  sorl ON sorl.SOPOrderReturnID    = sor.SOPOrderReturnID
LEFT  JOIN  S200_LIVE.dbo.SLCustomerAccount   cust ON cust.SLCustomerAccountID = sor.CustomerID
WHERE
        sor.DocumentTypeID   = 0                  -- sales orders, not returns
    AND sor.DocumentStatusID IN (0,1)             -- live and on hold
    AND sorl.LineTypeID      = 0                  -- product lines only; no free text, no comments
    AND (sorl.StockUnitLineQuantity - ISNULL(sorl.StockUnitDespRcptQuantity,0)) > 0

UNION ALL

/* -------------------------------------------------------- OLIVER HARVEY -- */
SELECT
    'OLIVER HARVEY',
    'OH-SO-' + CAST(sorl.SOPOrderReturnLineID AS varchar(20)),
    LTRIM(RTRIM(sorl.ItemCode)),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(sorl.ItemDescription,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    sor.DocumentNo,
    sorl.PrintSequenceNumber,
    ISNULL(cust.CustomerAccountNumber,''),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(cust.CustomerAccountName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(sor.CustomerDocumentNo,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    CONVERT(varchar(10), COALESCE(sor.PromisedDeliveryDate,  sorl.PromisedDeliveryDate,
                                  sor.RequestedDeliveryDate, sorl.RequestedDeliveryDate), 23),
    CAST(sorl.StockUnitLineQuantity AS decimal(18,2)),
    CAST(ISNULL(sorl.StockUnitDespRcptQuantity,0) AS decimal(18,2)),
    CAST(sorl.StockUnitLineQuantity - ISNULL(sorl.StockUnitDespRcptQuantity,0) AS decimal(18,2)),
    CAST(ISNULL(sorl.StockUnitAllocatedQuantity,0) AS decimal(18,2)),
    ISNULL(CAST(sorl.SOPOrderFulfilmentMethodID AS varchar(10)),''),
    ISNULL((SELECT TOP 1 lpo.DocumentNo
            FROM  OliverHarveyLive.dbo.MMS123BackToBackPO b
            JOIN  OliverHarveyLive.dbo.POPOrderReturn lpo ON lpo.POPOrderReturnID = b.POPOrderReturnID
            WHERE b.SOPOrderReturnID = sor.SOPOrderReturnID
            ORDER BY lpo.DocumentNo),''),
    CAST((SELECT COUNT(*) FROM OliverHarveyLive.dbo.MMS123BackToBackPO b
          WHERE b.SOPOrderReturnID = sor.SOPOrderReturnID) AS varchar(10)),
    CASE WHEN cust.CustomerAccountNumber = 'TIB003' THEN 'Y' ELSE '' END,
    CAST(sor.DocumentStatusID AS varchar(10)),
    ISNULL(CONVERT(varchar(10), sor.DocumentDate, 23),''),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(sor.UserName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))
FROM        OliverHarveyLive.dbo.SOPOrderReturn      sor
INNER JOIN  OliverHarveyLive.dbo.SOPOrderReturnLine  sorl ON sorl.SOPOrderReturnID    = sor.SOPOrderReturnID
LEFT  JOIN  OliverHarveyLive.dbo.SLCustomerAccount   cust ON cust.SLCustomerAccountID = sor.CustomerID
WHERE
        sor.DocumentTypeID   = 0
    AND sor.DocumentStatusID IN (0,1)
    AND sorl.LineTypeID      = 0
    AND (sorl.StockUnitLineQuantity - ISNULL(sorl.StockUnitDespRcptQuantity,0)) > 0
),

po AS (

/* ---------------------------------------------------------------- TIBARD -- */
SELECT
    'TIBARD'                                                    AS Company,
    'TIB-PO-' + CAST(porl.POPOrderReturnLineID AS varchar(20))  AS RowKey,
    LTRIM(RTRIM(porl.ItemCode))                                 AS ProductCode,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(porl.ItemDescription,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS Description,
    por.DocumentNo                                              AS DocNo,
    porl.PrintSequenceNumber                                    AS LineSeq,
    ISNULL(supp.SupplierAccountNumber,'')                       AS AccountNo,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(supp.SupplierAccountName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS AccountName,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(por.SupplierDocumentNo,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS Reference,
    /* POP lines carry no delivery date of their own - header only. Blank if
       the buyer never entered one; the app treats blank as "date unknown". */
    ISNULL(CONVERT(varchar(10), por.RequestedDeliveryDate, 23),'')
                                                                AS DateISO,
    CAST(porl.StockUnitLineQuantity AS decimal(18,2))           AS Qty1,
    CAST(ISNULL(porl.StockUnitRcptRtnQuantity,0) AS decimal(18,2))
                                                                AS Qty2,
    CAST(porl.StockUnitLineQuantity - ISNULL(porl.StockUnitRcptRtnQuantity,0) AS decimal(18,2))
                                                                AS Qty3,
    CAST(NULL AS decimal(18,2))                                 AS Qty4,
    ''                                                          AS FulfilMethodID,
    /* The sales order this PO was generated from, via MMS123BackToBackPO. */
    ISNULL((SELECT TOP 1 lso.DocumentNo
            FROM  S200_LIVE.dbo.MMS123BackToBackPO b
            JOIN  S200_LIVE.dbo.SOPOrderReturn lso ON lso.SOPOrderReturnID = b.SOPOrderReturnID
            WHERE b.POPOrderReturnID = por.POPOrderReturnID
            ORDER BY lso.DocumentNo),'')                        AS LinkID,
    CAST((SELECT COUNT(*) FROM S200_LIVE.dbo.MMS123BackToBackPO b
          WHERE b.POPOrderReturnID = por.POPOrderReturnID) AS varchar(10))
                                                                AS B2BCount,
    /* Tibard does not currently buy from OH. If it ever does, add that
       supplier account number here the same way as TIB001 below. */
    ''                                                          AS Intercompany,
    CAST(por.DocumentStatusID AS varchar(10))                   AS DocStatusID,
    ISNULL(CONVERT(varchar(10), por.DocumentDate, 23),'')       AS OrderDate,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(por.UserName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS EnteredBy
FROM        S200_LIVE.dbo.POPOrderReturn      por
INNER JOIN  S200_LIVE.dbo.POPOrderReturnLine  porl ON porl.POPOrderReturnID    = por.POPOrderReturnID
LEFT  JOIN  S200_LIVE.dbo.PLSupplierAccount   supp ON supp.PLSupplierAccountID = por.SupplierID
WHERE
        por.DocumentTypeID   = 0                  -- purchase orders, not returns
    AND por.DocumentStatusID IN (0,1)             -- live and on hold (see STATUS FILTERS)
    AND porl.LineTypeID      = 0                  -- product lines only
    AND (porl.StockUnitLineQuantity - ISNULL(porl.StockUnitRcptRtnQuantity,0)) > 0

UNION ALL

/* -------------------------------------------------------- OLIVER HARVEY -- */
SELECT
    'OLIVER HARVEY',
    'OH-PO-' + CAST(porl.POPOrderReturnLineID AS varchar(20)),
    LTRIM(RTRIM(porl.ItemCode)),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(porl.ItemDescription,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    por.DocumentNo,
    porl.PrintSequenceNumber,
    ISNULL(supp.SupplierAccountNumber,''),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(supp.SupplierAccountName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(por.SupplierDocumentNo,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    ISNULL(CONVERT(varchar(10), por.RequestedDeliveryDate, 23),''),
    CAST(porl.StockUnitLineQuantity AS decimal(18,2)),
    CAST(ISNULL(porl.StockUnitRcptRtnQuantity,0) AS decimal(18,2)),
    CAST(porl.StockUnitLineQuantity - ISNULL(porl.StockUnitRcptRtnQuantity,0) AS decimal(18,2)),
    CAST(NULL AS decimal(18,2)),
    '',
    ISNULL((SELECT TOP 1 lso.DocumentNo
            FROM  OliverHarveyLive.dbo.MMS123BackToBackPO b
            JOIN  OliverHarveyLive.dbo.SOPOrderReturn lso ON lso.SOPOrderReturnID = b.SOPOrderReturnID
            WHERE b.POPOrderReturnID = por.POPOrderReturnID
            ORDER BY lso.DocumentNo),''),
    CAST((SELECT COUNT(*) FROM OliverHarveyLive.dbo.MMS123BackToBackPO b
          WHERE b.POPOrderReturnID = por.POPOrderReturnID) AS varchar(10)),
    /* OH buying from Tibard. TIB001 = "Tibard Ltd" in OH's purchase ledger. */
    CASE WHEN supp.SupplierAccountNumber = 'TIB001' THEN 'Y' ELSE '' END,
    CAST(por.DocumentStatusID AS varchar(10)),
    ISNULL(CONVERT(varchar(10), por.DocumentDate, 23),''),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(por.UserName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))
FROM        OliverHarveyLive.dbo.POPOrderReturn      por
INNER JOIN  OliverHarveyLive.dbo.POPOrderReturnLine  porl ON porl.POPOrderReturnID    = por.POPOrderReturnID
LEFT  JOIN  OliverHarveyLive.dbo.PLSupplierAccount   supp ON supp.PLSupplierAccountID = por.SupplierID
WHERE
        por.DocumentTypeID   = 0
    AND por.DocumentStatusID IN (0,1)
    AND porl.LineTypeID      = 0
    AND (porl.StockUnitLineQuantity - ISNULL(porl.StockUnitRcptRtnQuantity,0)) > 0
),

/* Every code that appears on a live SO or PO line, per company. Only these
   get a STK row - the stock file is far too big to send whole. */
codes AS (
    SELECT Company, ProductCode FROM so
    UNION
    SELECT Company, ProductCode FROM po
),

/* Back-to-back history per code: how many generated POs in the last 12
   months contained it. Any value > 0 marks a code the buyer normally orders
   back to back, so an SO line for it with no linked PO is a miss. */
b2b12 AS (
    SELECT 'TIBARD' AS Company, LTRIM(RTRIM(lpl.ItemCode)) AS ProductCode,
           COUNT(DISTINCT b.POPOrderReturnID) AS N
    FROM   S200_LIVE.dbo.MMS123BackToBackPO  b
    JOIN   S200_LIVE.dbo.POPOrderReturn      lpo ON lpo.POPOrderReturnID = b.POPOrderReturnID
    JOIN   S200_LIVE.dbo.POPOrderReturnLine  lpl ON lpl.POPOrderReturnID = lpo.POPOrderReturnID
    WHERE  lpo.DocumentDate >= DATEADD(month, -12, GETDATE())
    GROUP BY LTRIM(RTRIM(lpl.ItemCode))
    UNION ALL
    SELECT 'OLIVER HARVEY', LTRIM(RTRIM(lpl.ItemCode)), COUNT(DISTINCT b.POPOrderReturnID)
    FROM   OliverHarveyLive.dbo.MMS123BackToBackPO  b
    JOIN   OliverHarveyLive.dbo.POPOrderReturn      lpo ON lpo.POPOrderReturnID = b.POPOrderReturnID
    JOIN   OliverHarveyLive.dbo.POPOrderReturnLine  lpl ON lpl.POPOrderReturnID = lpo.POPOrderReturnID
    WHERE  lpo.DocumentDate >= DATEADD(month, -12, GETDATE())
    GROUP BY LTRIM(RTRIM(lpl.ItemCode))
),

stk AS (

/* ---------------------------------------------------------------- TIBARD -- */
SELECT
    'TIBARD'                                                    AS Company,
    'TIB-STK-' + c.ProductCode                                  AS RowKey,
    c.ProductCode,
    CASE WHEN si.Code IS NULL THEN 'CODE NOT IN STOCK FILE'
         ELSE LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(si.Name,''),
              CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))) END  AS Description,
    ISNULL(ps.SupplierAccountNumber,'')                         AS AccountNo,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(ps.SupplierAccountName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS AccountName,
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(ps.SupplierStockCode,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' ')))            AS Reference,
    CAST(ISNULL(wh.InStock,0)          AS decimal(18,2))        AS Qty1,
    CAST(ISNULL(wh.Allocated,0)        AS decimal(18,2))        AS Qty2,
    CAST(ISNULL(si.FreeStockQuantity,0) AS decimal(18,2))       AS Qty3,
    CAST(ISNULL(wh.OnPO,0)             AS decimal(18,2))        AS Qty4,
    ISNULL(CAST(si.SOPOrderFulfilmentMethodID AS varchar(10)),'')
                                                                AS FulfilMethodID,
    LTRIM(RTRIM(ISNULL(si.Manufacturer,'')))                    AS Manufacturer,
    /* Tibard: Stock Held is its own analysis code. */
    CASE WHEN ISNULL(si.AnalysisCode3,'') = 'Yes' THEN 'Yes' ELSE '' END
                                                                AS StockHeld,
    ''                                                          AS WebsiteOH,
    ISNULL(pg.Code,'')                                          AS ProductGroup,
    ISNULL(CAST(si.BOMItemTypeID AS varchar(10)),'')            AS BOMItemTypeID,
    ISNULL(CAST(ps.LeadTime AS varchar(10)),'')                 AS LeadTime,
    ISNULL(CAST(ps.LeadTimeUnitID AS varchar(10)),'')           AS LeadTimeUnitID,
    CAST(ps.MinimumOrderQuantity AS decimal(18,2))              AS MOQ,
    ISNULL(CAST(bb.N AS varchar(10)),'0')                       AS B2B12m
FROM        codes c
LEFT  JOIN  S200_LIVE.dbo.StockItem     si ON si.Code             = c.ProductCode
LEFT  JOIN  b2b12                       bb ON bb.Company = 'TIBARD' AND bb.ProductCode = c.ProductCode
LEFT  JOIN  S200_LIVE.dbo.ProductGroup  pg ON pg.ProductGroupID   = si.ProductGroupID
/* Stock across every warehouse the item is set up in. */
OUTER APPLY (
    SELECT  SUM(wi.ConfirmedQtyInStock)                                 AS InStock,
            SUM(ISNULL(wi.QuantityAllocatedSOP,0) + ISNULL(wi.QuantityAllocatedStock,0)
              + ISNULL(wi.QuantityAllocatedBOM,0))                      AS Allocated,
            SUM(wi.QuantityOnPOPOrder)                                  AS OnPO
    FROM    S200_LIVE.dbo.WarehouseItem wi
    WHERE   wi.ItemID = si.ItemID
) wh
/* Preferred supplier first; otherwise the one most recently ordered from. */
OUTER APPLY (
    SELECT TOP 1 supp.SupplierAccountNumber, supp.SupplierAccountName,
           sis.SupplierStockCode, sis.LeadTime, sis.LeadTimeUnitID, sis.MinimumOrderQuantity
    FROM   S200_LIVE.dbo.StockItemSupplier sis
    LEFT JOIN S200_LIVE.dbo.PLSupplierAccount supp ON supp.PLSupplierAccountID = sis.SupplierID
    WHERE  sis.ItemID = si.ItemID
    ORDER BY sis.Preferred DESC, sis.DateLastOrder DESC
) ps
WHERE c.Company = 'TIBARD'

UNION ALL

/* -------------------------------------------------------- OLIVER HARVEY -- */
SELECT
    'OLIVER HARVEY',
    'OH-STK-' + c.ProductCode,
    c.ProductCode,
    CASE WHEN si.Code IS NULL THEN 'CODE NOT IN STOCK FILE'
         ELSE LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(si.Name,''),
              CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))) END,
    ISNULL(ps.SupplierAccountNumber,''),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(ps.SupplierAccountName,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(ISNULL(ps.SupplierStockCode,''),
        CHAR(9),' '), CHAR(13),' '), CHAR(10),' '))),
    CAST(ISNULL(wh.InStock,0)          AS decimal(18,2)),
    CAST(ISNULL(wh.Allocated,0)        AS decimal(18,2)),
    CAST(ISNULL(si.FreeStockQuantity,0) AS decimal(18,2)),
    CAST(ISNULL(wh.OnPO,0)             AS decimal(18,2)),
    ISNULL(CAST(si.SOPOrderFulfilmentMethodID AS varchar(10)),''),
    LTRIM(RTRIM(ISNULL(si.Manufacturer,''))),
    /* OH: Stock Held OR Website OR stock held at Tibard under the same code.
       Same three-way rule as the special makes query - do not tidy it to
       match the Tibard block, the two companies use the codes differently. */
    CASE WHEN ISNULL(si.AnalysisCode3,'')  = 'Yes'
           OR ISNULL(si.AnalysisCode7,'')  = 'Yes'
           OR ISNULL(tsi.AnalysisCode3,'') = 'Yes' THEN 'Yes' ELSE '' END,
    CASE WHEN ISNULL(si.AnalysisCode7,'')  = 'Yes' THEN 'Yes' ELSE '' END,
    ISNULL(pg.Code,''),
    ISNULL(CAST(si.BOMItemTypeID AS varchar(10)),''),
    ISNULL(CAST(ps.LeadTime AS varchar(10)),''),
    ISNULL(CAST(ps.LeadTimeUnitID AS varchar(10)),''),
    CAST(ps.MinimumOrderQuantity AS decimal(18,2)),
    ISNULL(CAST(bb.N AS varchar(10)),'0')
FROM        codes c
LEFT  JOIN  OliverHarveyLive.dbo.StockItem     si  ON si.Code            = c.ProductCode
LEFT  JOIN  b2b12                              bb  ON bb.Company = 'OLIVER HARVEY' AND bb.ProductCode = c.ProductCode
LEFT  JOIN  S200_LIVE.dbo.StockItem            tsi ON tsi.Code           = c.ProductCode   -- Tibard's record, same code
LEFT  JOIN  OliverHarveyLive.dbo.ProductGroup  pg  ON pg.ProductGroupID  = si.ProductGroupID
OUTER APPLY (
    SELECT  SUM(wi.ConfirmedQtyInStock)                                 AS InStock,
            SUM(ISNULL(wi.QuantityAllocatedSOP,0) + ISNULL(wi.QuantityAllocatedStock,0)
              + ISNULL(wi.QuantityAllocatedBOM,0))                      AS Allocated,
            SUM(wi.QuantityOnPOPOrder)                                  AS OnPO
    FROM    OliverHarveyLive.dbo.WarehouseItem wi
    WHERE   wi.ItemID = si.ItemID
) wh
OUTER APPLY (
    SELECT TOP 1 supp.SupplierAccountNumber, supp.SupplierAccountName,
           sis.SupplierStockCode, sis.LeadTime, sis.LeadTimeUnitID, sis.MinimumOrderQuantity
    FROM   OliverHarveyLive.dbo.StockItemSupplier sis
    LEFT JOIN OliverHarveyLive.dbo.PLSupplierAccount supp ON supp.PLSupplierAccountID = sis.SupplierID
    WHERE  sis.ItemID = si.ItemID
    ORDER BY sis.Preferred DESC, sis.DateLastOrder DESC
) ps
WHERE c.Company = 'OLIVER HARVEY'
),

/* One shape for all three row types. Columns the row type does not use are
   blank (text) or NULL (numbers) - both arrive as an empty cell when pasted. */
allrows AS (
    SELECT 'SO' AS RowType, Company, RowKey, ProductCode, Description, DocNo, LineSeq,
           AccountNo, AccountName, Reference, DateISO, Qty1, Qty2, Qty3, Qty4,
           FulfilMethodID, LinkID, B2BCount, Intercompany,
           '' AS Manufacturer, '' AS StockHeld, '' AS WebsiteOH, '' AS ProductGroup,
           '' AS BOMItemTypeID, '' AS LeadTime, '' AS LeadTimeUnitID,
           CAST(NULL AS decimal(18,2)) AS MOQ, DocStatusID, OrderDate, EnteredBy
    FROM   so
    UNION ALL
    SELECT 'PO', Company, RowKey, ProductCode, Description, DocNo, LineSeq,
           AccountNo, AccountName, Reference, DateISO, Qty1, Qty2, Qty3, Qty4,
           FulfilMethodID, LinkID, B2BCount, Intercompany,
           '', '', '', '', '', '', '', CAST(NULL AS decimal(18,2)), DocStatusID, OrderDate, EnteredBy
    FROM   po
    UNION ALL
    SELECT 'STK', Company, RowKey, ProductCode, Description, '' AS DocNo, CAST(NULL AS smallint) AS LineSeq,
           AccountNo, AccountName, Reference, '' AS DateISO, Qty1, Qty2, Qty3, Qty4,
           FulfilMethodID, '' AS LinkID, B2B12m AS B2BCount, '' AS Intercompany,
           Manufacturer, StockHeld, WebsiteOH, ProductGroup,
           BOMItemTypeID, LeadTime, LeadTimeUnitID, MOQ, '' AS DocStatusID, '' AS OrderDate, '' AS EnteredBy
    FROM   stk
)

SELECT  RowType, Company, RowKey, ProductCode, Description, DocNo, LineSeq,
        AccountNo, AccountName, Reference, DateISO, Qty1, Qty2, Qty3, Qty4,
        FulfilMethodID, LinkID, B2BCount, Intercompany,
        Manufacturer, StockHeld, WebsiteOH, ProductGroup,
        BOMItemTypeID, LeadTime, LeadTimeUnitID, MOQ, DocStatusID, OrderDate, EnteredBy
FROM    allrows
ORDER BY CASE RowType WHEN 'SO' THEN 1 WHEN 'PO' THEN 2 ELSE 3 END,
         Company, ProductCode, DocNo, LineSeq;
