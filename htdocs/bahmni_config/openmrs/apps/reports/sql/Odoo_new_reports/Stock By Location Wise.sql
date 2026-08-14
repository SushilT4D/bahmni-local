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
   
    sp.mrp AS "MRP",
    sq.cost as "cost",
    sp.sale_price AS "Sale Price",
    sq.qty AS "Quantity",
    pu.name AS "Unit of Measure",
    sl.name AS "Location",
    sp.name AS "Lot/Serial Number",
    sp.life_date AS "Expiry Date",
    sq.in_date AS "Incoming Date",
    
    sq.in_date AS "Stock Date",
    
    (sq.qty * sq.cost) AS "Inventory Value"
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
WHERE AND sp.life_date BETWEEN '#startDate#'AND '#endDate#'

ORDER BY
    pt.name, sp.name,sl.name;
