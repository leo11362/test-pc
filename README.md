# Test PC avant achat

## Lancer le test

1. Appuie sur **Windows + R**
2. Colle cette ligne puis **Entrée** :

```
powershell -ep bypass -c "[Net.ServicePointManager]::SecurityProtocol='Tls12';irm https://raw.githubusercontent.com/leo11362/test-pc/main/test-pc.ps1 -OutFile $env:TEMP\t.ps1;powershell -ep bypass -f $env:TEMP\t.ps1"
```

3. Clique sur **Oui** quand Windows demande les droits administrateur

Le test dure ~4 min et ouvre un rapport avec un diagnostic (vert / orange / rouge).
La commande marche aussi dans l'Invite de commandes (cmd) ou PowerShell.

La config attendue de l'annonce se modifie en haut de `test-pc.ps1` (bloc `$ANNONCE`).
