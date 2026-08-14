WITH stock_data AS (
    SELECT 
        pt.name AS "Product",
        CASE 
            WHEN pp.active = TRUE THEN 'Available'
            ELSE 'Inactive'
        END AS "Status",
        CASE 
            WHEN pt.type = 'product' THEN 'Stockable'
            WHEN pt.type = 'consu' THEN 'Consumable'
            ELSE 'Service'
        END AS "Product Type",
        pt.name AS "Drug Name",
        rp.Name AS "Manufacturer",
        pt.list_price AS "MRP",
        sm.price_unit AS "Cost",
        pt.list_price AS "Sale Price",
        sq.qty AS "Quantity",
        pu.name AS "Unit of Measure",
        sl.name AS "Location",
        sp.name AS "Lot/Serial Number",
        sp.life_date AS "Expiry Date",
        sm.origin AS "Source/PO Number",
        sq.in_date AS "Stock Date",
        sm.state AS "Stock Move State",
        po.invoice_status AS "Invoice Status",
        COALESCE(sm.product_qty, 0) AS "Stock Movement",
        sq.in_date
    FROM
        stock_quant sq
    LEFT JOIN
        stock_location sl ON sq.location_id = sl.id
    JOIN
        product_product pp ON sq.product_id = pp.id
    JOIN
        product_template pt ON pp.product_tmpl_id = pt.id
    LEFT JOIN
        product_uom pu ON pt.uom_id = pu.id
    LEFT JOIN
        stock_production_lot sp ON sq.lot_id = sp.id
    LEFT JOIN
        stock_move sm ON sq.product_id = sm.product_id
    LEFT JOIN 
        purchase_order po ON sm.origin = po.name
    LEFT JOIN
        purchase_order_line pol ON po.id = pol.order_id
    LEFT JOIN
        res_partner rp ON pol.manufacturer = rp.id
    WHERE
        sl.usage = 'internal' -- Retrieves only internal stock locations
        AND pt.active = TRUE -- Filters only active products
        AND sm.state = 'done' -- Completed stock moves
        AND po.invoice_status = 'invoiced' -- Completed invoices
        AND sq.in_date BETWEEN '#startDate#'AND '#endDate#' 
)
SELECT 
    "Product",
    "Status",
    "Product Type",
    "Drug Name",
    "Manufacturer",
    "MRP",
    "Cost",
    "Sale Price",
    "Unit of Measure",
    "Location",
    "Lot/Serial Number",
    "Expiry Date",
    "Source/PO Number",
    SUM(CASE WHEN DATE_TRUNC('month', "Stock Date") = DATE_TRUNC('month', CURRENT_DATE) THEN "Quantity" ELSE 0 END) AS "Opening Stock",
    SUM(CASE WHEN DATE_TRUNC('month', "Stock Date") = DATE_TRUNC('month', CURRENT_DATE) THEN "Stock Movement" ELSE 0 END) AS "Received Stock",
    SUM(CASE WHEN DATE_TRUNC('month', "Stock Date") = DATE_TRUNC('month', CURRENT_DATE) THEN "Quantity" - "Stock Movement" ELSE 0 END) AS "Closing Stock"
FROM 
    stock_data
GROUP BY 
    "Product", "Status", "Product Type", "Drug Name", "Manufacturer", "MRP", 
    "Cost", "Sale Price", "Unit of Measure", "Location", "Lot/Serial Number", 
    "Expiry Date", "Source/PO Number"
ORDER BY 
    "Product", "Location";
