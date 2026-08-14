SELECT DISTINCT 
    po.name AS "Purchase Order no", 
    rp.name AS "Vendor",
    po.partner_ref AS "Vendor Reference",
    po.date_order AS "Date",
    pt.name AS "Product Name",
    pol.name AS "description",
    rp1.name AS "Manufacturer Name",
    po.date_planned AS "Scheduled Date",
    pol.product_qty AS "Order quantity",
    pol.qty_received AS "Received Qty",
    pol.qty_invoiced AS "Billed Qty",
    pu.name AS "Product Unit Of Measure",
    sh.serial_number AS "Batch/Lot NO.",
    pol.price_unit AS "Unit Price",
    pol.mrp AS "MRP",
    at.name AS "Tax Name",
    ai.state AS "Status Of PO/Billing Status",
    pol.price_tax AS "Taxed Amount",
    pol.price_subtotal AS "Untaxed Amount",
    pol.price_total AS "Total"
FROM
    purchase_order po
LEFT JOIN purchase_order_line pol ON po.id = pol.order_id
LEFT JOIN res_partner rp ON po.partner_id = rp.id 
LEFT JOIN product_product pp ON pol.product_id = pp.id 
LEFT JOIN product_template pt ON pp.product_tmpl_id = pt.id 
LEFT JOIN account_invoice_line ail ON pol.id = ail.purchase_line_id
LEFT JOIN account_invoice_line_tax ailt ON ail.id = ailt.invoice_line_id
LEFT JOIN account_tax at ON ailt.tax_id = at.id 
LEFT JOIN account_invoice ai ON po.name = ai.origin
LEFT JOIN product_uom pu ON pol.product_uom = pu.id 
LEFT JOIN res_partner rp1 ON pol.manufacturer = rp1.id
join stock_move sm on pol.id = sm.purchase_line_id
join stock_history sh on sm.id = sh.move_id

where  po.date_order BETWEEN '#startDate#'AND '#endDate#'

ORDER BY 
    po.name;