// Runs a connector's transform chain, the way Kafka Connect applies it, on
// made-up change records that carry a row, and prints what each becomes.
//
//   java -cp <Connect and Debezium jars> RowFilterChainProbe.java CONFIG RECORDS
//
// CONFIG: the connector's configuration, one "<key><TAB><value>" per line.
// RECORDS: one "<topic><TAB><key column><TAB><key value><TAB><op><TAB><row column><TAB><row value>"
//   per line; op c or u puts the row in `after`, d in `before`, t is the
//   tombstone after a delete (no value at all). A composite key lists its
//   columns and its values comma-separated, in the same order; a value of
//   digits is an integer, any other a string.
// Prints "kept" or "dropped" per record, in order. A step that cannot be
// configured prints "configure-failed <reason>" and exits 3.
import java.nio.file.*;
import java.util.*;
import org.apache.kafka.connect.data.*;
import org.apache.kafka.connect.source.SourceRecord;
import org.apache.kafka.connect.transforms.Transformation;
import org.apache.kafka.connect.transforms.predicates.Predicate;

public class RowFilterChainProbe {
  static Map<String, String> sub(Map<String, String> cfg, String prefix, Set<String> skip) {
    Map<String, String> m = new HashMap<>();
    for (Map.Entry<String, String> e : cfg.entrySet())
      if (e.getKey().startsWith(prefix) && !skip.contains(e.getKey().substring(prefix.length())))
        m.put(e.getKey().substring(prefix.length()), e.getValue());
    return m;
  }

  @SuppressWarnings({"unchecked", "rawtypes"})
  public static void main(String[] a) throws Exception {
    Map<String, String> cfg = new HashMap<>();
    for (String l : Files.readAllLines(Paths.get(a[0]))) {
      int i = l.indexOf('\t');
      if (i > 0) cfg.put(l.substring(0, i), l.substring(i + 1));
    }
    List<Transformation<SourceRecord>> steps = new ArrayList<>();
    List<Predicate<SourceRecord>> preds = new ArrayList<>();
    try {
      for (String alias : cfg.getOrDefault("transforms", "").split(",")) {
        alias = alias.trim();
        if (alias.isEmpty()) continue;
        String p = "transforms." + alias + ".";
        Transformation<SourceRecord> t = (Transformation<SourceRecord>) Class.forName(cfg.get(p + "type")).getDeclaredConstructor().newInstance();
        t.configure(sub(cfg, p, Set.of("type", "predicate", "negate")));
        steps.add(t);
        String pa = cfg.get(p + "predicate");
        Predicate<SourceRecord> pr = null;
        if (pa != null) {
          String pp = "predicates." + pa + ".";
          pr = (Predicate<SourceRecord>) Class.forName(cfg.get(pp + "type")).getDeclaredConstructor().newInstance();
          pr.configure(sub(cfg, pp, Set.of("type")));
        }
        preds.add(pr);
      }
    } catch (Throwable e) {
      Throwable c = e;
      while (c.getCause() != null) c = c.getCause();
      System.out.println("configure-failed " + c.getClass().getSimpleName() + ": " + c.getMessage());
      System.exit(3);
    }
    for (String l : Files.readAllLines(Paths.get(a[1]))) {
      if (l.isBlank()) continue;
      String[] f = l.split("\t");
      String[] kc = f[1].split(","), kv = f[2].split(",");
      SchemaBuilder kb = SchemaBuilder.struct().name(f[0] + ".Key");
      for (int i = 0; i < kc.length; i++) kb.field(kc[i], kv[i].matches("[0-9]+") ? Schema.INT32_SCHEMA : Schema.STRING_SCHEMA);
      Schema ks = kb.build();
      Struct key = new Struct(ks);
      for (int i = 0; i < kc.length; i++) key.put(kc[i], kv[i].matches("[0-9]+") ? (Object) Integer.valueOf(kv[i]) : kv[i]);
      Schema vs = null;
      Struct val = null;
      if (!f[3].equals("t")) {
        SchemaBuilder rb = SchemaBuilder.struct().name(f[0] + ".Value").optional();
        for (Field kf : ks.fields()) rb.field(kf.name(), kf.schema());
        if (ks.field(f[4]) == null) rb.field(f[4], Schema.INT32_SCHEMA);
        Schema rs = rb.build();
        Struct row = new Struct(rs);
        for (Field kf : ks.fields()) row.put(kf.name(), key.get(kf));
        if (ks.field(f[4]) == null) row.put(f[4], Integer.valueOf(f[5]));
        vs = SchemaBuilder.struct().name(f[0] + ".Envelope")
            .field("before", rs).field("after", rs).field("op", Schema.STRING_SCHEMA).build();
        val = new Struct(vs).put("op", f[3]);
        if (f[3].equals("d")) val.put("before", row); else val.put("after", row);
      }
      SourceRecord r = new SourceRecord(null, null, f[0], 0, ks, key, vs, val);
      for (int i = 0; i < steps.size() && r != null; i++)
        if (preds.get(i) == null || preds.get(i).test(r)) r = steps.get(i).apply(r);
      System.out.println(r == null ? "dropped" : "kept");
    }
  }
}
