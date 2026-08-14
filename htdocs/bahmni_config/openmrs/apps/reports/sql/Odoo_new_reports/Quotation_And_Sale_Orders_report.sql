SELECT
  sale_order.name AS name,
  res_partner.name AS partner_name,
  CAST(sale_order.date_order AS date) AS date_order,
  sale_order.provider_name AS provider_name,
  sale_shop.name AS shop_name,
  product_template.name AS product_name,
  sale_order_line.name AS line_name,
  CAST(sale_order_line.expiry_date AS date) AS expiry_date,
  sale_order_line.product_uom_qty AS product_uom_qty,
  sale_order_line.qty_delivered AS qty_delivered,
  sale_order_line.price_tax AS price_tax,
  sale_order_line.price_unit AS price_unit,
  sale_order_line.price_subtotal AS price_subtotal,
  sale_order_line.price_total AS price_total,
  account_invoice.state AS invoice_state,
  product_uom.name AS uom_name,
  stock_production_lot.name AS lot_name
FROM
  sale_order
LEFT JOIN sale_order_line ON sale_order.id = sale_order_line.order_id
LEFT JOIN product_product ON sale_order_line.product_id = product_product.id
LEFT JOIN product_template ON product_product.product_tmpl_id = product_template.id
LEFT JOIN res_partner ON sale_order.partner_id = res_partner.id
LEFT JOIN product_uom ON sale_order_line.product_uom = product_uom.id
LEFT JOIN sale_shop ON sale_order.shop_id = sale_shop.id
LEFT JOIN account_invoice ON sale_order.name = account_invoice.origin
LEFT JOIN stock_production_lot ON sale_order_line.lot_id = stock_production_lot.id
  where sale_order.date_order BETWEEN '#startDate#'AND '#endDate#'
GROUP BY
  sale_order.name,
  res_partner.name,
  CAST(sale_order.date_order AS date),
  sale_order.provider_name,
  sale_shop.name,
  product_template.name,
  sale_order_line.name,
  CAST(sale_order_line.expiry_date AS date),
  sale_order_line.product_uom_qty,
  sale_order_line.qty_delivered,
  sale_order_line.price_tax,
  sale_order_line.price_unit,
  sale_order_line.price_subtotal,
  sale_order_line.price_total,
  account_invoice.state,
  product_uom.name,
  stock_production_lot.name

ORDER BY
  res_partner.name ASC,
  sale_order.name ASC,
  CAST(sale_order.date_order AS date) ASC,
  sale_order.provider_name ASC,
  sale_shop.name ASC,
  product_template.name ASC,
  sale_order_line.name ASC,
  CAST(sale_order_line.expiry_date AS date) ASC,
  sale_order_line.product_uom_qty ASC,
  sale_order_line.qty_delivered ASC,
  sale_order_line.price_tax ASC,
  sale_order_line.price_unit ASC,
  sale_order_line.price_subtotal ASC,
  sale_order_line.price_total ASC,
  account_invoice.state ASC,
  product_uom.name ASC,
  stock_production_lot.name ASC;
