// Evaluates one filter condition through a JSR-223 script engine, the way the
// Debezium Filter step does: compiled once, then run with the record bound as
// key, value and topic. The key is a map from column to value here (the
// condition reads it with key.get(column), which a Connect Struct answers the
// same way).
//
//   java -cp <groovy and groovy-jsr223 jars> Jsr223Probe.java LANGUAGE CONDITION RECORDS
//
// RECORDS: as FilterChainProbe.java. Prints "kept" or "dropped" per record; an
// engine that is missing prints "configure-failed <reason>" and exits 3.
import java.nio.file.*;
import java.util.*;
import javax.script.*;

public class Jsr223Probe {
  public static void main(String[] a) throws Exception {
    ScriptEngine engine = new ScriptEngineManager().getEngineByName(a[0]);
    if (engine == null) {
      System.out.println("configure-failed no " + a[0] + " script engine on the classpath");
      System.exit(3);
    }
    CompiledScript cs = ((Compilable) engine).compile(a[1]);
    for (String l : Files.readAllLines(Paths.get(a[2]))) {
      if (l.isBlank()) continue;
      String[] f = l.split("\t");
      Bindings b = engine.createBindings();
      Map<String, Object> key = new HashMap<>();
      key.put(f[1], Integer.valueOf(f[2]));
      b.put("key", key);
      b.put("value", f[3].equals("t") ? null : Map.of("op", f[3]));
      b.put("topic", f[0]);
      Object r = cs.eval(b);
      System.out.println(Boolean.TRUE.equals(r) ? "kept" : "dropped");
    }
  }
}
