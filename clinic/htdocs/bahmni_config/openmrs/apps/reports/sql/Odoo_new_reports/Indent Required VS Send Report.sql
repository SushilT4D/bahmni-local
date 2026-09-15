SELECT DISTINCT
    mi.name AS "Indent No",
    CASE 
        WHEN mi.Requirement = '1' THEN 'Ordinary'
        ELSE 'Urgent'
    END AS "Requirement",
    mi.indent_date AS "Indent Date",
    mi.required_date AS "Required Date",
    mi.issued_date AS "Approve Date",
    pt.name AS "Product",
    mipl.product_uom_qty AS "Quantity Required",
    pu.name AS "Unit",
    sl.name AS "Source Location",
    dl.name AS "Destination Location",
    mipl.name AS "Description",
    sm.product_qty AS "Quantity Sent",
    st.serial_number AS "Batch/Lot No.",
    sm.price_unit AS "Unit Price"
FROM
    mrp_indent mi
JOIN
    mrp_indent_product_lines mipl ON mipl.indent_id = mi.id
JOIN
    product_uom pu ON pu.id = mipl.product_uom
JOIN
    product_product pp ON pp.id = mipl.product_id
JOIN
    product_template pt ON pt.id = pp.product_tmpl_id
JOIN
    stock_location sl ON sl.id = mipl.location_id
JOIN
    stock_location dl ON dl.id = mipl.location_dest_id
LEFT JOIN
    stock_move sm ON sm.origin = mi.name AND sm.product_id = mipl.product_id
LEFT JOIN
    stock_history st ON mi.name = st.Source AND st.product_id = mipl.product_id
WHERE 
    mi.state = 'done' and mi.indent_date BETWEEN '#startDate#'AND '#endDate#'
ORDER BY
    mi.name;
