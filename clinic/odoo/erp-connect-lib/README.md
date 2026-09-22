# erp-connect-lib — Apache HttpClient 5 for `odoo-connect`

Three jars the `bahmni/odoo-connect` image needs and does not ship.
`openerp-client`'s `XMLClient.setTimeout` builds Spring 6's
`HttpComponentsClientHttpRequestFactory`, which `spring-web-6.0.19` compiles
against HttpClient 5 (`org.apache.hc.*`); the WAR carries only HttpClient 4, so
every Odoo XML-RPC call throws `NoClassDefFoundError`. Upstream catches
`Throwable` and logs it, so customers are still written -- the cost is one
30-line stack trace per event. These jars stop that. They do not restore the
configured reply timeout: Spring 6.0's `setReadTimeout` on this factory is a
no-op (it logs "has no effect" once), so that timeout was never applied and
still is not -- a hung Odoo still stalls the feed worker.

`docker-compose.override.yml` bind-mounts these into the exploded WAR's
`WEB-INF/lib`. Versions are the ones Spring Boot 3.0.13's BOM manages for that
spring-web. Source: Maven Central, `org.apache.httpcomponents.{client5,core5}`;
verify with `shasum -a1 -c SHA1SUMS`. Remove the mounts, and this directory,
once an upstream image tag ships HttpClient 5 in the WAR.
