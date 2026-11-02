# Test PC avant achat

Sur le PC à tester : clic droit sur **Démarrer** → **Terminal (administrateur)**, puis colle :

```
irm https://raw.githubusercontent.com/leo11362/test-pc/main/test-pc.ps1 -OutFile $env:TEMP\t.ps1; powershell -ep bypass -f $env:TEMP\t.ps1
```

Le test dure ~4 min et ouvre un rapport avec un diagnostic (vert / orange / rouge).
La config attendue de l'annonce se modifie en haut de `test-pc.ps1` (bloc `$ANNONCE`).
