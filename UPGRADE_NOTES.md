# Anpassungen für BS in 3.0.0

Die Container-Services unterstützen canteen_native und die drei Tonflaschenzustände zusätzlich zu den BCC-Behältern. Der Füllvorgang übernimmt die Haltbarkeit, und Aufbereitung erhält Material und Restmenge. PlayerFinder nutzt weiterhin IsSickByCharId. BLN-HUD, deutsche Sprache, Durstwerte 12/10, Krankheitsdauer 3600 Sekunden und 5 Schaden je 15 Sekunden bleiben eingestellt.

ConsumeContainer(source, 'bucket', itemId, true) leert beim Farming die gesamte gewählte Kanne. Goldwäsche verwendet denselben Export ohne viertes Argument für eine Portion. Nur bcc-water tauscht die Kanne aus oder wickelt ihren Bruch ab. Rezepte verbrauchen weiterhin die konfigurierte Anzahl ganzer Flaschen.

Der automatische Item-Seed ist aus. Auch ein manueller Seed erhält vorhandene Itemdefinitionen. Die Aufbereitungstablette wird gezielt angelegt. Nach Updates mit Altbestand, verschiedenen Haltbarkeiten, Tonflaschen, Trinkschlauch, vollem Inventar sowie Farming, Goldwäsche, Aufbereitung und PlayerFinder prüfen.
