SELECT DISTINCT
    sp.life_date AS "Expiry Date",
    sp.name AS "Lot/Serial Number",
    pt.name AS "Product",
    rp.Name AS "Manufacturer",
    pt.list_price AS "MRP",
    sm.price_unit AS "Cost",
    pt.list_price AS "Sale Price",
    sm.origin AS "PO Number",
    sq.qty AS "Quantity",
    pu.name AS "Unit of Measure",
    sl.name AS "Location",
    sq.in_date AS "Incoming Date",
    (sq.qty * sm.price_unit) AS "Inventory Value"
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
    AND sp.life_date IS NOT NULL -- Ensure expiry date exists
    AND sp.life_date > CURRENT_DATE -- Only include items expiring after today
    AND sp.life_date <= (CURRENT_DATE + INTERVAL '60 DAYS') -- Filter for medicines expiring within the next 30 days
    AND sm.origin LIKE 'PO%' 
    AND sp.life_date BETWEEN '#startDate#'AND '#endDate#'
ORDER BY
    sp.life_date, pt.name, sm.origin;
