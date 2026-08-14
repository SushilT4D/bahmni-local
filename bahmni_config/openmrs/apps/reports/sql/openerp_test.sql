SELECT
srp.product_id,
srp.prodlot_id,
srp.qty
            from stock_report_prodlots srp
            inner join stock_production_lot spl on spl.id=prodlot_id inner join product_product pp on pp.id=srp.product_id
            inner join stock_location sl on sl.id=srp.location_id and srp.location_id=11
            inner join product_template pt on pt.id=pp.id
            inner join product_uom pu on pu.id=pt.uom_po_id
            left join product_generic pg on pp.product_generic_id=pg.id
            order by pp.name_template;

