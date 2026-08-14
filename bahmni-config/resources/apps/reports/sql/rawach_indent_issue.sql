Select
mi.name "Indent",
mipl.product_id "Product Code",
mipl.name "Product",
pt.drug "Generic Name",
mipl.product_uom_qty "Quantity",
pu.name "UoM"
From mrp_indent mi
Join mrp_indent_product_lines mipl on mipl.indent_id = mi.id
Join product_uom pu on pu.id = mipl.product_uom
Join product_product pp on pp.id = mipl.product_id
Join product_template pt on pt.id = pp.product_tmpl_id
Where mipl.location_dest_id = 19
And mi.state = 'done'
And mi.indent_date between '#startDate#'AND '#endDate#'
Order by mi.name;