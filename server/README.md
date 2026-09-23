# NAS Fleet archive

Single-household deployment for the DS423+ (2 GB). This is a recording backend,
not a vehicle command proxy or an APNs push server. The default Compose project
is isolated from the Internet and exposes its API on NAS loopback only.

## Components and data contract

- Apache Kafka 3.9.1, one local broker, 256 MiB JVM heap, 512 MiB container limit.
  Four explicitly created topics retain the original vehicle JSON packets.
  Broker flush is requested per message; this is still a single-machine system,
  not replication or protection against disk failure.
- Python archive, 128 MiB limit, SQLite WAL with synchronous=FULL. A raw packet
  and local offset commit together **before** the Kafka consumer offset commits.
  Replayed packets are deduplicated by canonical payload, VIN and record type.
  Invalid records remain in storage and never enter the measurement API.
- The initial Kafka buffer is capped at seven days / 256 MiB per topic. SQLite
  history has no automatic deletion. Back up the archive volume and monitor
  NAS disk space. Prolonged disk or machine failure can still lose observations.
- API `/v1/telemetry?vin=...&after=...` returns original payloads, an increasing
  cursor and `more`. At most 40 packets / about 4.5 MB per response. Authentication
  is a 48-byte random URL-safe bearer token in the archive volume's `api-token`
  file, mode 0600. Tokens and VINs are not printed to application access logs.
- iOS stores this token in Keychain, accepts HTTPS origins only, refuses all
  redirects, and saves a per-origin/per-VIN cursor only after local persistence.
  Opening the Telemetry screen resumes synchronization; this does not imply
  background APNs or full historical trip reconstruction is already enabled.

## Internal installation

Upload `Dockerfile`, `store.py`, `docker-compose.yml` together to
`/volume1/docker/tesla-fleet`. In Container Manager create `tesla-fleet` using
that existing Compose file; leave Web Station portal disabled. The initialization
container exits successfully after creating the new volumes and private token.
The Kafka and archive containers should both become healthy.

The synthetic CI suite checks storage restart, replay deduplication, vehicle
isolation, original timestamps, page continuation, container startup and restart.
An idle CI run measured about 318 MiB Kafka + 17 MiB archive; this is not a
measurement of actual vehicle traffic or NAS peak memory.

## Vehicle ingress activation gate

The base installation alone receives **no vehicle telemetry**. Before enabling
`docker-compose.telemetry.yml`:

1. Assign a public DNS hostname with a valid public-CA certificate and renewal.
   QuickConnect's NAS management URL is not the telemetry endpoint.
2. Keep mTLS termination at `tesla/fleet-telemetry:v0.9.4`. A normal DSM HTTP
   reverse proxy that terminates TLS cannot replace the vehicle mTLS listener.
   Vehicle TCP traffic must reach its TLS listener directly (proposed 8443).
3. Place full certificate chain and key in the restricted `certs/` folder; copy
   `telemetry-config.example.json` to `telemetry-config.json`. Never commit keys.
4. Obtain action-time approval before publishing the listener / changing router
   exposure. Do not publish Kafka ports, SQLite files, or DSM administration.
5. Run Tesla's official `check_server_cert.sh` from an external network. Configure
   the existing registered Tesla application's signed `fleet_telemetry_config`
   using its virtual key and OAuth permissions; wait for `synced=true` and verify
   a real vehicle event in the archive. Existing application domain/key hosting
   is separate from this server's telemetry hostname.
6. Publish the app archive API through a valid HTTPS endpoint (separate from
   vehicle mTLS), still requiring its bearer token. Configure that HTTPS origin
   and token in the app's battery/Telemetry screen.

APNs signing credentials, push entitlement and device registration remain a
separate required integration for alerts when the phone app is not running.

## Stop / rollback

Stop this project's containers in Container Manager. Keep the named data volumes
and existing NAS services. Do not select removal of volumes or delete the archive.
Only a disposable synthetic CI project uses `docker compose down -v`.

Sources: [Tesla receiver](https://github.com/teslamotors/fleet-telemetry/tree/v0.9.4),
[Kafka Docker](https://kafka.apache.org/39/getting-started/docker/),
[Synology projects](https://kb.synology.com/en-us/DSM/help/ContainerManager/docker_project?version=7).
