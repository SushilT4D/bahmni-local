// Runs a connector's transform chain, the way Kafka Connect applies it, on
// made-up Debezium change events from a multi-table topic: each event carries
// the source block (with the table it came from), the op, and the row in
// `after` (or `before` for a delete). Prints what each becomes.
//
//   java -cp <Connect and Debezium jars> EnvelopeFilterProbe.java CONFIG RECORDS
//
// CONFIG: the connector's configuration, one "<key><TAB><value>" per line.
// RECORDS: one "<topic><TAB><table><TAB><op><TAB><id><TAB><column><TAB><value><TAB><type>"
//   per line. The row holds id, and <column> as well unless it is id. <type> is
//   double (a numeric column read with decimal.handling.mode=double) or long.
//   op c, u or r puts the row in `after`, d in `before`, t is the tombstone
//   after a delete (no value at all).
// Prints "kept" or "dropped" per record, in order. A step that cannot be
// configured prints "configure-failed <reason>" and exits 3.
import java.nio.file.*;
import java.util.*;
import org.apache.kafka.connect.data.*;
import org.apache.kafka.connect.source.SourceRecord;
import org.apache.kafka.connect.transforms.Transformation;

public class EnvelopeFilterProbe {
  @SuppressWarnings({"unchecked", "rawtypes"})
  public static void main(String[] a) throws Exception {
    Map<String, String> cfg = new HashMap<>();
    for (String l : Files.readAllLines(Paths.get(a[0]))) {
      int i = l.indexOf('\t');
      if (i > 0) cfg.put(l.substring(0, i), l.substring(i + 1));
    }
    List<Transformation<SourceRecord>> steps = new ArrayList<>();
    try {
      for (String alias : cfg.getOrDefault("transforms", "").split(",")) {
        alias = alias.trim();
        if (alias.isEmpty()) continue;
        String p = "transforms." + alias + ".";
        Transformation<SourceRecord> t = (Transformation<SourceRecord>) Class.forName(cfg.get(p + "type")).getDeclaredConstructor().newInstance();
        Map<String, String> m = new HashMap<>();
        for (Map.Entry<String, String> e : cfg.entrySet())
          if (e.getKey().startsWith(p) && !e.getKey().equals(p + "type")) m.put(e.getKey().substring(p.length()), e.getValue());
        t.configure(m);
        steps.add(t);
      }
    } catch (Throwable e) {
      Throwable c = e;
      while (c.getCause() != null) c = c.getCause();
      System.out.println("configure-failed " + c.getClass().getSimpleName() + ": " + c.getMessage());
      System.exit(3);
    }
    Schema src = SchemaBuilder.struct().name("io.debezium.connector.postgresql.Source")
        .field("db", Schema.STRING_SCHEMA).field("schema", Schema.STRING_SCHEMA).field("table", Schema.STRING_SCHEMA).build();
    for (String l : Files.readAllLines(Paths.get(a[1]))) {
      if (l.isBlank()) continue;
      String[] f = l.split("\t");
      String topic = f[0], table = f[1], op = f[2], col = f[4], type = f[6];
      Schema num = type.equals("double") ? Schema.FLOAT64_SCHEMA : Schema.INT64_SCHEMA;
      Schema ks = SchemaBuilder.struct().name(topic + ".Key").field("id", num).build();
      Struct key = new Struct(ks).put("id", type.equals("double") ? (Object) Double.valueOf(f[3]) : (Object) Long.valueOf(f[3]));
      Schema vs = null;
      Struct val = null;
      if (!op.equals("t")) {
        SchemaBuilder rb = SchemaBuilder.struct().name(topic + "." + table + ".Value").optional().field("id", num);
        if (!col.equals("id")) rb.field(col, SchemaBuilder.type(num.type()).optional().build());
        Schema rs = rb.build();
        Struct row = new Struct(rs).put("id", key.get("id"));
        if (!col.equals("id") && !f[5].equals("null"))
          row.put(col, type.equals("double") ? (Object) Double.valueOf(f[5]) : (Object) Long.valueOf(f[5]));
        vs = SchemaBuilder.struct().name(topic + ".Envelope")
            .field("before", rs).field("after", rs).field("source", src).field("op", Schema.STRING_SCHEMA).build();
        val = new Struct(vs).put("op", op).put("source", new Struct(src).put("db", "openelis").put("schema", "clinlims").put("table", table));
        if (op.equals("d")) val.put("before", row); else val.put("after", row);
      }
      SourceRecord r = new SourceRecord(null, null, topic, 0, ks, key, vs, val);
      for (int i = 0; i < steps.size() && r != null; i++) r = steps.get(i).apply(r);
      System.out.println(r == null ? "dropped" : "kept");
    }
  }
}
