# Eigene Anpassungen an bcc-water

## Erhaltener Stand 2.5.1

BSDev und BS-Live verwenden denselben angepassten Stand. Zusätzlich zur
Standardfeldflasche werden `canteen_native` sowie die drei Tonflaschenzustände
`tonflasche`, `tonflasche_frischwasser` und `tonflasche_wasser` unterstützt.
`server/main.lua` bewahrt die gewählte Iteminstanz, deren Füllstand und den
konfigurierten Haltbarkeitsverbrauch. Der Export `IsSickByCharId` wird von
`zata_PlayerFinder` verwendet.

## Upstream 3.0.0 noch nicht integriert

Der Integrationsversuch gegen `ca78a51` wurde im isolierten Worktree verworfen.
Upstream ersetzt `server/main.lua` durch Services und entfernt dabei unsere
Mehrfachbehälterbehandlung sowie den Krankheitsexport. Ein verlustfreies Update
benötigt eine gezielte Portierung und Funktionsprüfungen dieser Erweiterungen.
Auch die geänderte Behälternutzung, Haltbarkeit und Wasseraufbereitung müssen
vor einer Umstellung abgestimmt werden.

Beide Datenbanken verwenden Seed-Version 2. Der neue Seeder mit Version 4
überschreibt bestehende Labels, Beschreibungen und Limits. Vor seiner Übernahme
müssen diese Definitionen geschützt und neue Items separat geprüft werden.
Aktuell sind die benötigten Definitionen einschließlich Trinkschlauch und
Tonflaschen auf beiden Servern identisch vorhanden. Es wurde kein SQL ausgeführt.
