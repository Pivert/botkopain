# BotKopain - Bot joueur francophone pour Luanti

BotKopain est un bot joueur intelligent pour le serveur "Un Monde Merveilleux" de Luanti (ex-Minetest). Il utilise l'API EdenAI pour fournir des réponses contextuelles et intelligentes en français.

## 🆕 Nouveautés

**Version 2.0 - Connexion directe EdenAI**
- ✅ Suppression du gateway Python - connexion directe à EdenAI
- ✅ Intégration native dans Lua
- ✅ Gestion améliorée de l'historique des conversations
- ✅ Configuration simplifiée via minetest.conf
- ✅ Meilleures performances et fiabilité

## 📋 Configuration requise

### 1. Configuration EdenAI
Ajoutez ces lignes dans votre `minetest.conf`:

```ini
# Configuration EdenAI (obligatoire)
botkopain_edenai_api_key = votre_cle_api_edenai
botkopain_edenai_project_id = votre_project_id_edenai

# Activation de l'API HTTP (obligatoire)
secure.http_mods = botkopain
```

### 2. Obtenir vos clés EdenAI
1. Créez un compte sur [EdenAI](https://www.edenai.co)
2. Créez un nouveau projet
3. Récupérez votre `API Key` et `Project ID`
4. Ajoutez-les dans votre `minetest.conf`

## 🎮 Utilisation

### Commandes disponibles

#### Chat public
Parlez simplement dans le chat - BotKopain répondra automatiquement si vous êtes seul sur le serveur.

#### Chat privé
```
/bk <message>     - Envoyer un message privé à BotKopain
/bk !public       - Partager la dernière conversation avec tout le monde
/bk !public3      - Partager les 3 dernières conversations avec tout le monde
```

#### Commandes administratives
```
/bkstatus         - Vérifier l'état de la connexion EdenAI
/bk_clear [joueur] - Effacer l'historique de conversation (admin)
```

#### Partage de conversations
```
/bk message !public3  - Partager vos 3 dernières conversations privées (avec nouveau message)
/bk !public3         - Partager vos 3 dernières conversations privées (sans nouveau message)
/bk !public          - Partager la dernière conversation privée (sans nouveau message)
```

## 🧠 Fonctionnalités

### Mémoire conversationnelle
- **Historique persistant** : BotKopain se souvient de vos conversations
- **Compactage intelligent** : Les anciennes conversations sont automatiquement compactées
- **Contexte multijoueur** : Prend en compte les autres joueurs en ligne
- **Séparation public/privé** : Historiques séparés pour les chats publics et privés

### Partage intelligent
- **!public** : Partage les conversations sans envoyer de requête inutile à EdenAI
- **!public3** : Partage un nombre spécifique de conversations
- **Optimisation** : Pas de requête API quand seule la commande de partage est utilisée

### Personnalité
- **Français obligatoire** : Toutes les réponses sont en français
- **Style concis** : Réponses courtes et directes, max 4 phrases
- **Comportement adaptatif** : S'adapte au style du joueur
- **Connaissance du jeu** : Maîtrise les mods du serveur (TechAge, animalia, etc.)

## 🔧 Installation

1. Téléchargez le mod et placez-le dans le dossier `mods/` de votre serveur
2. Renommez le dossier en `botkopain` si nécessaire
3. Configurez votre `minetest.conf` comme indiqué ci-dessus
4. Redémarrez le serveur

## 📁 Structure du mod

```
botkopain/
├── init.lua          # Module principal
├── edenai.lua        # Intégration EdenAI
├── mod.conf          # Configuration du mod
└── README.md         # Ce fichier
```

## 🚨 Dépannage

### "API HTTP non disponible" - Le problème le plus courant

**Symptômes :** Message instantané "BotKopain Erreur: API HTTP non disponible"

**Solutions :**
1. **Vérifiez la configuration** : `secure.http_mods = botkopain` doit être dans `minetest.conf`
2. **Redémarrez Luanti complètement** après modification
3. **Utilisez `/debug_http`** pour diagnostiquer
4. **Consultez le guide** : [DEPANNAGE.md](DEPANNAGE.md) pour des instructions détaillées

### BotKopain ne répond pas
1. Vérifiez `/bkstatus` pour la configuration
2. Utilisez `/bktest` pour tester la connexion
3. Vérifiez vos clés EdenAI

### Erreurs de connexion
- **API HTTP non disponible** : Voir guide ci-dessus
- **Configuration EdenAI manquante** : Ajoutez vos clés dans minetest.conf
- **Délai d'attente dépassé** : Vérifiez votre connexion internet

## 📝 Notes techniques

- **API utilisée** : EdenAI AskYoda v2
- **Modèle LLM** : Mistral Small Latest
- **Langue** : Français uniquement
- **Limite de tokens** : 150 par réponse
- **Historique** : 10 échanges récents + 5 compactés

## 🤝 Contribution

Ce mod est spécifiquement conçu pour le serveur "Un Monde Merveilleux". Pour contribuer ou adapter à votre serveur :

1. Modifiez `prompt.txt` pour adapter la personnalité
2. Ajustez les paramètres dans `edenai.lua`
3. Testez sur votre serveur de développement

## 📄 Licence

Voir le fichier LICENSE pour les détails de la licence.

---

**BotKopain** - Un compagnon francophone pour vos aventures Luanti ! 🎮🇫🇷