select sl.name as Location_Name,pp.name_template as Product_Name,pp.default_code as Code,spl.name as Serial_Number,
pu.name as Purchase_Unit,round(round(srp.qty)/round(1/pu.factor)) as Quantity,spl.life_date as Expiry_Date
from stock_report_prodlots srp
inner join stock_production_lot spl on spl.id=prodlot_id inner join product_product pp on pp.id=srp.product_id  and round(srp.qty)>0
inner join stock_location sl on sl.id=srp.location_id and srp.location_id=11
inner join  product_template pt on pt.id=pp.id
inner join product_uom pu on pu.id=pt.uom_po_id
order by pp.name_template;
