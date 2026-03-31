#!/usr/bin/env python3
"""
romm-download.py — Myrient ROM downloader for RomM on Synology NAS

Fuzzy-matches requested game names against Myrient's real directory listings,
so filename format differences (Rev A vs Rev 1, etc.) never cause 404s.

Run on NAS:
    nohup python3 /volume1/roms/romm-download.py > /volume1/roms/download.log 2>&1 &
    tail -f /volume1/roms/download.log
"""

import os, re, ssl, time, threading, urllib.request, urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed

# ── Config ──────────────────────────────────────────────────────────────────
NAS         = "/volume1/roms/roms"
NI          = "https://myrient.erista.me/files/No-Intro"
RD          = "https://myrient.erista.me/files/Redump"
MA          = "https://myrient.erista.me/files/MAME/ROMs%20(merged)"

MAX_WORKERS = 3
MAX_RETRIES = 5
CHUNK_SIZE  = 512 * 1024  # 512 KB

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode    = ssl.CERT_NONE
HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; RommDownloader/1.0)"}

_lock      = threading.Lock()
_dir_cache = {}   # base_url -> list of filenames

# ── Logging ─────────────────────────────────────────────────────────────────
def log(msg):
    with _lock:
        print(msg, flush=True)

# ── Directory listing (cached per URL) ──────────────────────────────────────
def list_dir(base_url):
    if base_url in _dir_cache:
        return _dir_cache[base_url]
    try:
        req  = urllib.request.Request(base_url + "/", headers=HEADERS)
        resp = urllib.request.urlopen(req, context=CTX, timeout=30)
        html = resp.read().decode("utf-8", errors="ignore")
        links = re.findall(r'href="([^"]+\.zip)"', html)
        files = [urllib.parse.unquote(l.split("/")[-1]) for l in links]
        _dir_cache[base_url] = files
        return files
    except Exception as e:
        log(f"  WARN: could not list {base_url}: {e}")
        _dir_cache[base_url] = []
        return []

# ── Fuzzy match ──────────────────────────────────────────────────────────────
# Tags that are noise when matching (prefer files WITHOUT these)
_BAD_TAGS = re.compile(
    r'\b(Beta|Proto|Pirate|Virtual Console|Animal Crossing|Capcom Town|'
    r'iam8bit|Retro-Bit|Zelda Collection|Promo|Demo|Sample|Kiosk|Rev 0|Video|Multiboot|eReader|Play-Yan)\b',
    re.IGNORECASE
)
# Strip revision/edition qualifiers for base comparison (NOT disc numbers)
_STRIP_JUNK = re.compile(
    r'\s*\((Rev \w+|Virtual Console|Animal Crossing|Capcom Town|iam8bit|'
    r'Retro-Bit|Zelda Collection|Arcade Mode|Simulation Mode)\)',
    re.IGNORECASE
)

def _disc(name):
    """Extract disc number string like '(Disc 1)' or '' if none."""
    m = re.search(r'\(Disc \d+[^)]*\)', name, re.IGNORECASE)
    return m.group(0).lower() if m else ""

def _base(name):
    """Return lowercase name without extension or junk qualifiers (keeps disc info)."""
    n = os.path.splitext(name)[0]
    n = _STRIP_JUNK.sub("", n).strip()
    return n.lower()

def fuzzy_match(wanted, candidates):
    """
    Given a wanted filename and a list of candidates from Myrient,
    return the best matching candidate filename (or None).
    Region preference: Europe > (Europe, USA) > World > USA > Japan-only.
    Disc numbers are respected — (Disc 1) only matches (Disc 1).
    Also prefers no bad tags and highest revision number.
    """
    w_base  = _base(wanted)
    w_disc  = _disc(wanted)

    # Extract the title part (before the first region qualifier)
    title_only = re.sub(r'\s*\(.*', '', os.path.splitext(wanted)[0]).strip().lower()

    scored = []
    for c in candidates:
        c_base  = _base(c)
        c_disc  = _disc(c)
        c_title = re.sub(r'\s*\(.*', '', os.path.splitext(c)[0]).strip().lower()
        # Disc numbers must match exactly (if wanted has a disc qualifier)
        if w_disc and c_disc != w_disc:
            continue
        # Must match on stripped base OR just title
        if c_base != w_base and c_title != title_only:
            continue
        # Score: lower is better
        score = 0
        if _BAD_TAGS.search(c):
            score += 1000
        # Region preference (Europe first)
        if re.search(r'\(Europe\)', c):
            score -= 40
        elif re.search(r'\(Europe,', c) or re.search(r', Europe\)', c):
            score -= 30   # (USA, Europe) or (Europe, ...) multi-region
        elif re.search(r'\(World\)', c):
            score -= 20
        elif re.search(r'\(USA\)', c) or re.search(r'\(USA,', c):
            score -= 10
        # Japan-only is last resort
        elif re.search(r'\(Japan\)', c) and not re.search(r'(USA|Europe|World)', c):
            score += 20
        # Prefer higher revision numbers
        rev = re.search(r'Rev (\d+)', c, re.IGNORECASE)
        if rev:
            score -= int(rev.group(1))
        scored.append((score, c))

    if not scored:
        return None
    scored.sort(key=lambda x: x[0])
    return scored[0][1]

# ── Download ─────────────────────────────────────────────────────────────────
def head_size(url):
    try:
        req  = urllib.request.Request(url, headers=HEADERS, method="HEAD")
        resp = urllib.request.urlopen(req, context=CTX, timeout=30)
        return int(resp.headers.get("Content-Length", 0))
    except:
        return 0

def download_one(base_url, dest_dir, wanted_name):
    """Resolve wanted_name against directory listing, then download."""
    os.makedirs(dest_dir, exist_ok=True)

    # Resolve actual filename
    candidates = list_dir(base_url)
    actual_name = fuzzy_match(wanted_name, candidates)
    if actual_name is None:
        log(f"  MISS  {wanted_name}  (not found in listing)")
        return False

    if actual_name != wanted_name:
        log(f"  MAP   {wanted_name}\n        → {actual_name}")

    url  = f"{base_url}/{urllib.parse.quote(actual_name)}"
    path = os.path.join(dest_dir, actual_name)

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            remote_size = head_size(url)
            local_size  = os.path.getsize(path) if os.path.exists(path) else 0

            if remote_size > 0 and local_size == remote_size:
                log(f"  SKIP  {actual_name}")
                return True

            hdrs = dict(HEADERS)
            if 0 < local_size < remote_size:
                hdrs["Range"] = f"bytes={local_size}-"
                mode   = "ab"
                offset = local_size
                log(f"  RESUME[{attempt}] {actual_name} +{(remote_size-local_size)//1048576}MB")
            else:
                mode   = "wb"
                offset = 0
                log(f"  START [{attempt}] {actual_name} {remote_size//1048576}MB")

            req  = urllib.request.Request(url, headers=hdrs)
            resp = urllib.request.urlopen(req, context=CTX, timeout=120)
            received = offset
            with open(path, mode) as fh:
                while True:
                    chunk = resp.read(CHUNK_SIZE)
                    if not chunk:
                        break
                    fh.write(chunk)
                    received += len(chunk)

            log(f"  DONE  {actual_name} {received//1048576}MB")
            return True

        except Exception as e:
            log(f"  ERR  [{attempt}/{MAX_RETRIES}] {actual_name}: {e}")
            if attempt < MAX_RETRIES:
                time.sleep(5 * attempt)

    log(f"  FAIL  {actual_name}")
    return False

# ── Task builder ─────────────────────────────────────────────────────────────
def tasks(dest, base_url, *games):
    return [(base_url, dest, g) for g in games]

ALL_TASKS = []

# ─── NES ────────────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/nes",
    f"{NI}/Nintendo%20-%20Nintendo%20Entertainment%20System%20(Headered)",
    "Super Mario Bros. (World).zip",
    "Super Mario Bros. 2 (USA) (Rev 1).zip",
    "Super Mario Bros. 3 (USA) (Rev 1).zip",
    "Legend of Zelda, The (USA) (Rev 1).zip",
    "Zelda II - The Adventure of Link (USA).zip",
    "Metroid (USA).zip",
    "Mega Man 2 (USA).zip",
    "Mega Man 3 (USA).zip",
    "Castlevania (USA) (Rev 1).zip",
    "Castlevania III - Dracula's Curse (USA).zip",
    "Contra (USA).zip",
    "Super C (USA).zip",
    "DuckTales (USA).zip",
    "Kirby's Adventure (USA) (Rev 1).zip",
    "Punch-Out!! (USA).zip",
    "Final Fantasy (USA).zip",
    "Dragon Warrior (USA) (Rev 1).zip",
    "Ninja Gaiden (USA).zip",
    "Ninja Gaiden II - The Dark Sword of Chaos (USA).zip",
    "Battletoads (USA).zip",
    "River City Ransom (USA).zip",
    "Bionic Commando (USA).zip",
    "Blaster Master (USA).zip",
    "Crystalis (USA).zip",
    "StarTropics (USA).zip",
    "Little Nemo - The Dream Master (USA).zip",
    "Guardian Legend, The (USA).zip",
    "Metal Storm (USA).zip",
    "Shatterhand (USA).zip",
    "Gargoyle's Quest II (USA).zip",
    "Battletoads & Double Dragon - The Ultimate Team (USA).zip",
    # extended list
    "Tetris (USA).zip",
    "Batman - The Video Game (USA).zip",
    "Excitebike (USA).zip",
    "Kid Icarus (USA, Europe).zip",
    "EarthBound Beginnings (USA).zip",
    "Adventure Island II (USA).zip",
    "Bubble Bobble (USA).zip",
    "Double Dragon II - The Revenge (USA).zip",
    "Shadowgate (USA).zip",
    "Maniac Mansion (USA).zip",
    "Rygar (USA).zip",
    "Mr. Gimmick (Europe).zip",
    "Micro Machines (USA, Europe).zip",
    "Faxanadu (USA).zip",
    "Gun-Nac (USA).zip",
    "Vice - Project Doom (USA).zip",
    "Little Samson (USA).zip",
    "Dragon Warrior IV (USA).zip",
    "Jackal (USA).zip",
    "Gradius (USA).zip",
    "Journey to Silius (USA).zip",
    "Willow (USA).zip",
    "Dr. Mario (USA).zip",
    "Life Force (USA).zip",
    "DuckTales 2 (USA).zip",
    "Chip 'n Dale Rescue Rangers (USA).zip",
    "G.I. Joe (USA).zip",
)

# ─── SNES ───────────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/snes",
    f"{NI}/Nintendo%20-%20Super%20Nintendo%20Entertainment%20System",
    "Super Mario World (USA).zip",
    "Legend of Zelda, The - A Link to the Past (USA).zip",
    "Super Metroid (USA).zip",
    "Chrono Trigger (USA).zip",
    "Final Fantasy III (USA).zip",
    "EarthBound (USA).zip",
    "Secret of Mana (USA).zip",
    "Super Mario RPG - Legend of the Seven Stars (USA).zip",
    "Mega Man X (USA).zip",
    "Donkey Kong Country (USA) (Rev 1).zip",
    "Donkey Kong Country 2 - Diddy's Kong Quest (USA) (Rev 1).zip",
    "Donkey Kong Country 3 - Dixie Kong's Double Trouble! (USA).zip",
    "Super Mario World 2 - Yoshi's Island (USA).zip",
    "Super Castlevania IV (USA).zip",
    "Contra III - The Alien Wars (USA).zip",
    "ActRaiser (USA).zip",
    "Terranigma (Europe).zip",
    "Lufia II - Rise of the Sinistrals (USA).zip",
    "Breath of Fire II (USA).zip",
    "Illusion of Gaia (USA).zip",
    "Super Mario Kart (USA).zip",
    "F-Zero (USA).zip",
    "Kirby Super Star (USA).zip",
    "Demon's Crest (USA).zip",
    "Zombies Ate My Neighbors (USA).zip",
    "Super Punch-Out!! (USA).zip",
    "Harvest Moon (USA).zip",
    "Soul Blazer (USA).zip",
    "Wild Guns (USA).zip",
    "Tales of Phantasia (USA) (En).zip",
    "Shadowrun (USA).zip",
    "Final Fantasy - Mystic Quest (USA).zip",
    # extended list
    "Super Mario All-Stars (USA).zip",
    "Street Fighter II Turbo - Hyper Fighting (USA).zip",
    "Star Fox (USA).zip",
    "U.N. Squadron (USA).zip",
    "Pocky & Rocky (USA).zip",
    "Skyblazer (USA).zip",
    "Rock n' Roll Racing (USA).zip",
    "Knights of the Round (USA).zip",
    "Mega Man 7 (USA).zip",
    "Tetris Attack (USA).zip",
    "Legend of the Mystical Ninja (USA).zip",
    "Pilotwings (USA).zip",
    "Super Bomberman (USA).zip",
    "Ogre Battle - The March of the Black Queen (USA).zip",
    "Secret of Evermore (USA).zip",
    "NBA Jam - Tournament Edition (USA).zip",
    "Mega Man X2 (USA).zip",
    "Earthworm Jim (USA).zip",
    "Blackthorne (USA).zip",
    "Space Megaforce (USA).zip",
    "Teenage Mutant Ninja Turtles IV - Turtles in Time (USA).zip",
)

# ─── N64 ────────────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/n64",
    f"{NI}/Nintendo%20-%20Nintendo%2064%20(BigEndian)",
    "Super Mario 64 (USA).zip",
    "Legend of Zelda, The - Ocarina of Time (USA).zip",
    "Legend of Zelda, The - Majora's Mask (USA).zip",
    "007 - GoldenEye (USA).zip",
    "Super Smash Bros. (USA).zip",
    "Mario Kart 64 (USA).zip",
    "Star Fox 64 (USA) (Rev 1).zip",
    "Banjo-Kazooie (USA) (Rev 1).zip",
    "Banjo-Tooie (USA).zip",
    "Paper Mario (USA).zip",
    "Donkey Kong 64 (USA).zip",
    "Perfect Dark (USA).zip",
    "Conker's Bad Fur Day (USA).zip",
    "F-Zero X (USA).zip",
    "Wave Race 64 (USA) (Rev 1).zip",
    "Blast Corps (USA) (Rev 1).zip",
    "Mischief Makers (USA).zip",
    "Sin and Punishment - Hoshi no Keishousha (Japan).zip",
    "Ogre Battle 64 - Person of Lordly Caliber (USA).zip",
    "Diddy Kong Racing (USA) (En,Fr) (Rev 1).zip",
    "1080 Snowboarding (Japan, USA) (En,Ja).zip",
    "Kirby 64 - The Crystal Shards (USA).zip",
    "Jet Force Gemini (USA).zip",
    "Harvest Moon 64 (USA).zip",
    "Mystical Ninja Starring Goemon (USA).zip",
    "Doom 64 (USA).zip",
    "Rocket - Robot on Wheels (USA).zip",
    "Snowboard Kids (USA).zip",
    "Pokemon Stadium 2 (USA).zip",
    "Pokemon Puzzle League (USA).zip",
    # extended list
    "Star Wars - Rogue Squadron (USA).zip",
    "Mario Party 2 (USA).zip",
    "Turok 2 - Seeds of Evil (USA).zip",
    "WWF No Mercy (USA).zip",
    "Rayman 2 - The Great Escape (USA).zip",
    "Resident Evil 2 (USA).zip",
    "Pokemon Snap (USA).zip",
    "Mario Tennis (USA).zip",
    "Tony Hawk's Pro Skater 2 (USA).zip",
    "StarCraft 64 (USA).zip",
    "Duke Nukem 64 (USA).zip",
    "Space Station Silicon Valley (USA).zip",
    "Worms Armageddon (USA).zip",
    "Mario Party 3 (USA).zip",
    "Beetle Adventure Racing (USA).zip",
    "Pilotwings 64 (USA).zip",
    "Snowboard Kids 2 (USA).zip",
    "Excitebike 64 (USA).zip",
    "Goemon's Great Adventure (USA).zip",
    "Star Wars - Episode I - Racer (USA).zip",
    "Gauntlet Legends (USA).zip",
    "WCW-nWo Revenge (USA).zip",
    "WinBack - Covert Operations (USA).zip",
    "Indiana Jones and the Infernal Machine (USA).zip",
    "Bomberman 64 (USA).zip",
)

# ─── GAME BOY ───────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/gb",
    f"{NI}/Nintendo%20-%20Game%20Boy",
    "Pokemon - Red Version (USA, Europe) (SGB Enhanced).zip",
    "Pokemon - Blue Version (USA, Europe) (SGB Enhanced).zip",
    "Tetris (World) (Rev 1).zip",
    "Legend of Zelda, The - Link's Awakening (USA, Europe).zip",
    "Super Mario Land (World) (Rev 1).zip",
    "Super Mario Land 2 - 6 Golden Coins (USA, Europe) (Rev 2).zip",
    "Kirby's Dream Land (USA, Europe).zip",
    "Kirby's Dream Land 2 (USA, Europe) (SGB Enhanced).zip",
    "Metroid II - Return of Samus (USA, Europe).zip",
    "Donkey Kong (USA, Europe) (SGB Enhanced).zip",
    "Wario Land - Super Mario Land 3 (USA, Europe) (SGB Enhanced).zip",
    "Gargoyle's Quest (USA, Europe).zip",
    "Final Fantasy Adventure (USA).zip",
    "Final Fantasy Legend, The (USA).zip",
    "Final Fantasy Legend II (USA).zip",
    "Final Fantasy Legend III (USA).zip",
    "Mega Man - Dr. Wily's Revenge (USA).zip",
    "Mega Man V (USA).zip",
    "Castlevania II - Belmont's Revenge (USA, Europe).zip",
    "Kid Icarus - Of Myths and Monsters (USA, Europe).zip",
    "Mario's Picross (USA, Europe).zip",
    "Mole Mania (USA, Europe).zip",
    "Operation C (USA).zip",
    "Dr. Mario (World) (Rev 1).zip",
    "Batman - The Video Game (USA, Europe).zip",
    "Avenging Spirit (USA, Europe).zip",
    "R-Type (USA, Europe).zip",
    "Balloon Kid (USA, Europe).zip",
    "Trip World (Europe).zip",
)

# ─── GAME BOY COLOR ─────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/gbc",
    f"{NI}/Nintendo%20-%20Game%20Boy%20Color",
    "Pokemon - Gold Version (USA, Europe).zip",
    "Pokemon - Silver Version (USA, Europe).zip",
    "Pokemon - Crystal Version (USA, Europe).zip",
    "Legend of Zelda, The - Oracle of Ages (USA, Europe).zip",
    "Legend of Zelda, The - Oracle of Seasons (USA, Europe).zip",
    "Legend of Zelda, The - Link's Awakening DX (USA, Europe).zip",
    "Wario Land 3 (USA, Europe).zip",
    "Wario Land II (USA, Europe).zip",
    "Dragon Warrior Monsters (USA) (SGB Enhanced).zip",
    "Dragon Warrior Monsters 2 - Cobi's Journey (USA).zip",
    "Dragon Warrior III (USA).zip",
    "Mario Tennis (USA).zip",
    "Shantae (USA).zip",
    "Metal Gear Solid (USA, Europe).zip",
    "Pokemon Trading Card Game (USA, Europe) (SGB Enhanced).zip",
    "Survival Kids (USA).zip",
    "Bionic Commando - Elite Forces (USA, Europe).zip",
    "Revelations - The Demon Slayer (USA).zip",
    "Mega Man Xtreme (USA, Europe).zip",
    "Mega Man Xtreme 2 (USA, Europe).zip",
    "Mario Golf (USA, Europe).zip",
    "Pokemon Pinball (USA, Europe) (Rumble Version) (SGB Enhanced).zip",
    "Tetris DX (USA, Europe).zip",
    "Game & Watch Gallery 2 (USA, Europe) (SGB Enhanced).zip",
    "Game & Watch Gallery 3 (USA, Europe).zip",
    "Alone in the Dark - The New Nightmare (USA, Europe).zip",
    "Wendy - Every Witch Way (USA).zip",
    "Hamtaro - Ham-Hams Unite! (Europe).zip",
    "Barbie - Fashion Pack Games (Europe).zip",
    "Barbie - Pet Rescue (Europe).zip",
)

# ─── GAME BOY ADVANCE ───────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/gba",
    f"{NI}/Nintendo%20-%20Game%20Boy%20Advance",
    "Pokemon - FireRed Version (USA, Europe) (Rev 1).zip",
    "Pokemon - Emerald Version (USA, Europe).zip",
    "Legend of Zelda, The - The Minish Cap (USA, Europe).zip",
    "Metroid - Fusion (USA, Europe).zip",
    "Metroid - Zero Mission (USA, Europe).zip",
    "Golden Sun (USA, Europe).zip",
    "Golden Sun - The Lost Age (USA, Europe).zip",
    "Fire Emblem (USA, Europe).zip",
    "Fire Emblem - The Sacred Stones (USA, Europe).zip",
    "Advance Wars (USA, Europe).zip",
    "Advance Wars 2 - Black Hole Rising (USA, Europe).zip",
    "Castlevania - Aria of Sorrow (USA).zip",
    "Castlevania - Circle of the Moon (USA, Europe).zip",
    "Castlevania - Harmony of Dissonance (USA).zip",
    "Mario & Luigi - Superstar Saga (USA, Europe).zip",
    "WarioWare, Inc. - Mega Microgame$! (USA).zip",
    "Kirby & The Amazing Mirror (USA, Europe).zip",
    "Mega Man Zero (USA).zip",
    "Mega Man Zero 2 (USA).zip",
    "Mega Man Zero 3 (USA).zip",
    "Mega Man Zero 4 (USA).zip",
    "Final Fantasy Tactics Advance (USA, Europe).zip",
    "Mother 3 (Japan).zip",
    "Drill Dozer (USA).zip",
    "Wario Land 4 (USA, Europe).zip",
    "Ninja Five-O (USA).zip",
    "Riviera - The Promised Land (USA).zip",
    "Gunstar Super Heroes (USA).zip",
    "Tactics Ogre - The Knight of Lodis (USA).zip",
    "Sword of Mana (USA, Europe).zip",
    # extended list
    "Astro Boy - Omega Factor (USA).zip",
    "Final Fantasy VI Advance (USA, Europe).zip",
    "Sonic Advance (USA, Europe).zip",
    "Klonoa - Empire of Dreams (USA, Europe).zip",
    "Harvest Moon - Friends of Mineral Town (USA, Europe).zip",
    "Game & Watch Gallery Advance (USA, Europe).zip",
    "F-Zero - GP Legend (USA, Europe).zip",
    "Mario vs. Donkey Kong (USA, Europe).zip",
    "Pokemon Mystery Dungeon - Red Rescue Team (USA, Europe).zip",
    "Boktai - The Sun Is in Your Hand (USA, Europe).zip",
    "Mega Man Battle Network 3 - Blue Version (USA).zip",
    "Kuru Kuru Kururin (Europe).zip",
    "Lufia - The Ruins of Lore (USA).zip",
    "Kingdom Hearts - Chain of Memories (USA).zip",
    "Street Fighter Alpha 3 (USA).zip",
    "Rayman Advance (USA, Europe).zip",
    "Mario Golf - Advance Tour (USA, Europe).zip",
    "Legend of Zelda, The - A Link to the Past & Four Swords (USA, Europe).zip",
    "Super Mario Advance 4 - Super Mario Bros. 3 (USA, Europe).zip",
    "WarioWare Twisted! (USA).zip",
    "Dr. Mario & Puzzle League (USA, Europe).zip",
    "Final Fantasy I & II - Dawn of Souls (USA, Europe).zip",
    "Sonic Advance 2 (USA, Europe).zip",
    "Kirby - Nightmare in Dream Land (USA, Europe).zip",
    "Mario Power Tennis (USA, Europe).zip",
    # Hamtaro / Barbie / Winx (GBA)
    "Hamtaro - Ham-Ham Heartbreak (Europe).zip",
    "Hamtaro - Rainbow Rescue (Europe).zip",
    "Hamtaro - Ham-Ham Games (Europe).zip",
    "Secret Agent Barbie - Royal Jewels Mission (Europe).zip",
    "Barbie - The Princess and the Pauper (Europe).zip",
    "Barbie and the Magic of Pegasus (Europe).zip",
    "Barbie in The 12 Dancing Princesses (Europe).zip",
    "Barbie as The Island Princess (Europe).zip",
    "Winx Club (Europe).zip",
    "Winx Club - Quest for the Codex (Europe).zip",
    "The Sims 2 (Europe).zip",
    "Disney's The Little Mermaid - Magic in Two Kingdoms (Europe).zip",
)

# ─── NINTENDO DS  (all Professor Layton DS) ─────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/nds",
    f"{NI}/Nintendo%20-%20Nintendo%20DS%20(Decrypted)",
    "Professor Layton and the Curious Village (Europe) (En,Fr,De,Es,It).zip",
    "Professor Layton and Pandora's Box (Europe) (En,Fr,De,Es,It).zip",
    "Professor Layton and the Lost Future (Europe) (En,Fr,De,Es,It).zip",
    "Professor Layton and the Spectre's Call (Europe) (En,Fr,De,Es,It).zip",
    "Pokemon - HeartGold Version (USA).zip",
    "Pokemon - SoulSilver Version (USA).zip",
    "Pokemon - Platinum Version (USA).zip",
    "Pokemon - Black Version (USA, Europe).zip",
    "Pokemon - White Version (USA, Europe).zip",
    "Legend of Zelda, The - Phantom Hourglass (USA).zip",
    "Legend of Zelda, The - Spirit Tracks (USA).zip",
    "Mario Kart DS (USA).zip",
    "New Super Mario Bros. (USA, Europe).zip",
    "Chrono Trigger (USA).zip",
    "Dragon Quest IV - Chapters of the Chosen (USA).zip",
    "Dragon Quest V - Hand of the Heavenly Bride (USA).zip",
    "Dragon Quest IX - Sentinels of the Starry Skies (USA).zip",
    "Castlevania - Dawn of Sorrow (USA).zip",
    "Castlevania - Portrait of Ruin (USA).zip",
    "Castlevania - Order of Ecclesia (USA).zip",
    "World Ends with You, The (USA).zip",
    "Phoenix Wright - Ace Attorney (USA).zip",
    "Phoenix Wright - Ace Attorney - Justice for All (USA).zip",
    "Phoenix Wright - Ace Attorney - Trials and Tribulations (USA).zip",
    "Advance Wars - Dual Strike (USA).zip",
    "Fire Emblem - Shadow Dragon (USA).zip",
    "Ghost Trick - Phantom Detective (USA).zip",
    "999 - Nine Hours, Nine Persons, Nine Doors (USA).zip",
    "Radiant Historia (USA).zip",
    "Elite Beat Agents (USA).zip",
    "Hotel Dusk - Room 215 (USA).zip",
    "Infinite Space (USA).zip",
    # extended list
    "Grand Theft Auto - Chinatown Wars (USA).zip",
    "Golden Sun - Dark Dawn (USA, Europe).zip",
    "Tetris DS (USA).zip",
    "Rhythm Heaven (USA).zip",
    "Resident Evil - Deadly Silence (USA).zip",
    "Mario & Luigi - Bowser's Inside Story (USA).zip",
    "Dragon Quest VI - Realms of Revelation (USA).zip",
    "Kirby Super Star Ultra (USA).zip",
    "Mario & Luigi - Partners in Time (USA, Europe).zip",
    "Animal Crossing - Wild World (USA).zip",
    "Picross 3D (USA, Europe).zip",
    "Meteos (USA).zip",
    "WarioWare - Touched! (USA).zip",
    "Trauma Center - Under the Knife (USA).zip",
    "Star Fox Command (USA).zip",
    "Sonic Rush (USA).zip",
    "Apollo Justice - Ace Attorney (USA).zip",
    "Kirby Mass Attack (USA).zip",
    "Bangai-O Spirits (USA).zip",
    "Henry Hatsworth in the Puzzling Adventure (USA).zip",
    "Kingdom Hearts - 358-2 Days (USA).zip",
    "Contra 4 (USA).zip",
    "Shin Megami Tensei - Strange Journey (USA).zip",
    "Okamiden (USA).zip",
    "Might & Magic - Clash of Heroes (USA).zip",
    "Mario Party DS (USA).zip",
    "Scribblenauts (USA).zip",
    "Ninja Gaiden - Dragon Sword (USA, Europe).zip",
    "Solatorobo - Red the Hunter (Europe).zip",
    "Last Window - The Secret of Cape West (Europe).zip",
    "42 All-Time Classics (Europe).zip",
    # Hamtaro / Barbie / Winx / kids (DS)
    "Hi! Hamtaro - Ham-Ham Challenge (Europe).zip",
    "Barbie - Jet, Set & Style! (Europe).zip",
    "Barbie and the Three Musketeers (Europe).zip",
    "Winx Club - Mission Enchantix (Europe).zip",
    "Winx Club - Secret Diary 2009 (Europe).zip",
    "Winx Club - Rockstars (Europe).zip",
    "Winx Club - Magical Fairy Party (Europe).zip",
    "Super Princess Peach (Europe).zip",
    "Style Boutique (Europe).zip",
    "Cooking Mama (Europe).zip",
    "Magician's Quest - Mysterious Times (Europe).zip",
    "Littlest Pet Shop - Garden (Europe).zip",
)

# ─── VIRTUAL BOY ────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/virtualboy",
    f"{NI}/Nintendo%20-%20Virtual%20Boy",
    "Wario Land (USA, Europe).zip",
    "Mario Tennis (USA, Europe).zip",
    "Galactic Pinball (USA).zip",
    "Jack Bros. (USA).zip",
    "Panic Bomber (USA).zip",
    "Teleroboxer (USA, Europe).zip",
    "Red Alarm (USA).zip",
    "Mario's Tennis (USA, Europe).zip",
    "Vertical Force (USA).zip",
    "Nester's Funky Bowling (USA).zip",
    "3-D Tetris (USA).zip",
)

# ─── PLAYSTATION 1 ──────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/psx",
    f"{RD}/Sony%20-%20PlayStation",
    "Final Fantasy VII (USA) (Disc 1).zip",
    "Final Fantasy VII (USA) (Disc 2).zip",
    "Final Fantasy VII (USA) (Disc 3).zip",
    "Final Fantasy VIII (USA) (Disc 1).zip",
    "Final Fantasy VIII (USA) (Disc 2).zip",
    "Final Fantasy VIII (USA) (Disc 3).zip",
    "Final Fantasy VIII (USA) (Disc 4).zip",
    "Final Fantasy IX (USA) (Disc 1).zip",
    "Final Fantasy IX (USA) (Disc 2).zip",
    "Final Fantasy IX (USA) (Disc 3).zip",
    "Final Fantasy IX (USA) (Disc 4).zip",
    "Metal Gear Solid (USA) (Disc 1).zip",
    "Metal Gear Solid (USA) (Disc 2).zip",
    "Castlevania - Symphony of the Night (USA).zip",
    "Resident Evil - Director's Cut (USA).zip",
    "Resident Evil 2 (USA) (Disc 1).zip",
    "Resident Evil 2 (USA) (Disc 2).zip",
    "Resident Evil 3 - Nemesis (USA).zip",
    "Silent Hill (USA).zip",
    "Chrono Cross (USA) (Disc 1).zip",
    "Chrono Cross (USA) (Disc 2).zip",
    "Xenogears (USA) (Disc 1).zip",
    "Xenogears (USA) (Disc 2).zip",
    "Vagrant Story (USA).zip",
    "Suikoden (USA).zip",
    "Suikoden II (USA).zip",
    "Parasite Eve (USA) (Disc 1).zip",
    "Parasite Eve (USA) (Disc 2).zip",
    "Legend of Dragoon, The (USA) (Disc 1).zip",
    "Legend of Dragoon, The (USA) (Disc 2).zip",
    "Legend of Dragoon, The (USA) (Disc 3).zip",
    "Legend of Dragoon, The (USA) (Disc 4).zip",
    "Crash Bandicoot (USA).zip",
    "Crash Bandicoot 2 - Cortex Strikes Back (USA).zip",
    "Crash Bandicoot - Warped (USA).zip",
    "Spyro the Dragon (USA).zip",
    "Spyro 2 - Ripto's Rage! (USA).zip",
    "Spyro - Year of the Dragon (USA).zip",
    "Tekken 3 (USA).zip",
    "Gran Turismo 2 (USA) (Disc 1) (Arcade Mode).zip",
    "Gran Turismo 2 (USA) (Disc 2) (Simulation Mode).zip",
    "Ape Escape (USA).zip",
    "MediEvil (USA).zip",
    "Dino Crisis (USA).zip",
    "Klonoa - Door to Phantomile (USA).zip",
    "Brave Fencer Musashi (USA).zip",
    "Legend of Mana (USA).zip",
    "Tomba! (USA).zip",
    "Tony Hawk's Pro Skater 2 (USA).zip",
    "Bushido Blade (USA).zip",
    # extended list
    "Wipeout 2097 (Europe).zip",
    "Legacy of Kain - Soul Reaver (USA).zip",
    "Tomb Raider (USA).zip",
    "Driver (USA).zip",
    "PaRappa the Rapper (USA).zip",
    "Oddworld - Abe's Oddysee (USA).zip",
    "Syphon Filter (USA).zip",
    "Wild Arms (USA).zip",
    "Alundra (USA).zip",
    "Ridge Racer Type 4 (USA).zip",
    "Tenchu - Stealth Assassins (USA).zip",
    "Soul Blade (Europe).zip",
    "Valkyrie Profile (USA) (Disc 1).zip",
    "Valkyrie Profile (USA) (Disc 2).zip",
    "Breath of Fire IV (USA) (Disc 1).zip",
    "Breath of Fire IV (USA) (Disc 2).zip",
    "Colin McRae Rally 2.0 (Europe).zip",
    "Mega Man X4 (USA).zip",
    "Grandia (USA) (Disc 1).zip",
    "Grandia (USA) (Disc 2).zip",
    "Street Fighter Alpha 3 (USA).zip",
    "Final Fantasy Tactics (USA).zip",
    "Rayman 2 - The Great Escape (USA).zip",
    "Persona 2 - Eternal Punishment (USA).zip",
    "WWF SmackDown! 2 - Know Your Role (USA).zip",
    "Twisted Metal 2 (USA).zip",
    "Gex - Enter the Gecko (USA).zip",
    "Barbie - Explorer (Europe).zip",
    "Barbie - Super Sports (Europe).zip",
)

# ─── PSP ────────────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/psp",
    f"{RD}/Sony%20-%20PlayStation%20Portable",
    "God of War - Chains of Olympus (USA).zip",
    "God of War - Ghost of Sparta (USA).zip",
    "Crisis Core - Final Fantasy VII (USA).zip",
    "Shin Megami Tensei - Persona 3 Portable (USA).zip",
    "Monster Hunter Freedom Unite (USA).zip",
    "Disgaea - Afternoon of Darkness (USA).zip",
    "Final Fantasy Tactics - The War of the Lions (USA).zip",
    "Metal Gear Solid - Peace Walker (USA).zip",
    "Patapon (USA).zip",
    "Patapon 2 (USA).zip",
    "LocoRoco (USA).zip",
    "LocoRoco 2 (USA).zip",
    "Lumines - Puzzle Fusion (USA).zip",
    "Daxter (USA).zip",
    "Jeanne d'Arc (USA).zip",
    "Valkyria Chronicles II (USA).zip",
    "Kingdom Hearts - Birth by Sleep (USA).zip",
    "Legend of Heroes, The - Trails in the Sky (USA).zip",
    "Tactics Ogre - Let Us Cling Together (USA).zip",
    "Half-Minute Hero (USA).zip",
    "Castlevania - The Dracula X Chronicles (USA).zip",
    "Mega Man - Maverick Hunter X (USA).zip",
    "Ys Seven (USA).zip",
    "Ys - The Oath in Felghana (USA).zip",
    "Dissidia 012 - Duodecim Final Fantasy (USA).zip",
    "Grand Theft Auto - Vice City Stories (USA).zip",
    "Grand Theft Auto - Liberty City Stories (USA).zip",
    "Corpse Party (USA).zip",
    "Wipeout Pure (USA).zip",
    "Killzone - Liberation (USA).zip",
    "Winx Club - Join the Club (Europe).zip",
)

# ─── SEGA MASTER SYSTEM ─────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/segaMS",
    f"{NI}/Sega%20-%20Master%20System%20-%20Mark%20III",
    "Alex Kidd in Miracle World (USA, Europe) (Rev 1).zip",
    "Phantasy Star (USA, Europe).zip",
    "Wonder Boy III - The Dragon's Trap (USA, Europe).zip",
    "Wonder Boy in Monster Land (USA, Europe) (En) (Rev 1).zip",
    "Sonic the Hedgehog (USA, Europe).zip",
    "Castle of Illusion Starring Mickey Mouse (USA, Europe).zip",
    "Shinobi (USA, Europe).zip",
    "Golden Axe Warrior (USA, Europe).zip",
    "R-Type (USA, Europe).zip",
    "Zillion (USA, Europe).zip",
    "Master of Darkness (USA, Europe).zip",
    "Psycho Fox (USA, Europe).zip",
    "Kenseiden (USA, Europe).zip",
    "Spellcaster (USA, Europe).zip",
    "Power Strike (USA, Europe).zip",
    "Land of Illusion Starring Mickey Mouse (USA, Europe).zip",
    "Double Dragon (USA, Europe).zip",
    "Space Harrier (USA, Europe).zip",
    "After Burner (USA, Europe).zip",
    "Ultima IV - Quest of the Avatar (USA, Europe).zip",
    "California Games (USA, Europe).zip",
    "Streets of Rage (USA, Europe).zip",
    "Rastan (USA, Europe).zip",
    "Hang On (USA, Europe).zip",
    "Psychic World (USA, Europe).zip",
)

# ─── SEGA GENESIS / MEGA DRIVE ──────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/segaMD",
    f"{NI}/Sega%20-%20Mega%20Drive%20-%20Genesis",
    "Sonic the Hedgehog (USA, Europe).zip",
    "Sonic the Hedgehog 2 (World) (Rev 1).zip",
    "Sonic the Hedgehog 3 (USA, Europe).zip",
    "Sonic & Knuckles + Sonic the Hedgehog 3 (World).zip",
    "Streets of Rage 2 (USA, Europe).zip",
    "Streets of Rage 3 (USA, Europe).zip",
    "Gunstar Heroes (USA, Europe).zip",
    "Phantasy Star IV (USA, Europe).zip",
    "Shining Force (USA, Europe).zip",
    "Shining Force II (USA, Europe).zip",
    "Castlevania - Bloodlines (USA).zip",
    "Contra - Hard Corps (USA, Korea).zip",
    "Comix Zone (USA, Europe).zip",
    "Vectorman (USA, Europe).zip",
    "Shinobi III - Return of the Ninja Master (USA, Europe).zip",
    "Thunder Force III (Japan, USA).zip",
    "Lightening Force - Quest for the Darkstar (USA).zip",
    "Ristar (USA, Europe).zip",
    "Rocket Knight Adventures (USA, Europe).zip",
    "Beyond Oasis (USA).zip",
    "Landstalker (USA, Europe).zip",
    "Toe Jam & Earl (World).zip",
    "Crusader of Centy (USA).zip",
    "Dynamite Headdy (USA, Europe).zip",
    "MUSHA - Metallic Uniframe Super Hybrid Armor (USA).zip",
    "Alien Soldier (Europe).zip",
    "Herzog Zwei (USA, Europe).zip",
    "Alisia Dragoon (USA, Europe).zip",
    "Zombies Ate My Neighbors (USA, Europe).zip",
    "Ranger-X (USA).zip",
)

# ─── SEGA GAME GEAR ─────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/segaGG",
    f"{NI}/Sega%20-%20Game%20Gear",
    "Sonic The Hedgehog - Triple Trouble (USA, Europe, Brazil) (En).zip",
    "Sonic the Hedgehog 2 (World).zip",
    "Sonic the Hedgehog (World).zip",
    "Shining Force - The Sword of Hajya (USA, Europe).zip",
    "Columns (World).zip",
    "Castle of Illusion Starring Mickey Mouse (USA, Europe).zip",
    "Shinobi (USA, Europe).zip",
    "Shinobi II - The Silent Fury (USA, Europe).zip",
    "GG Shinobi, The (Japan).zip",
    "Ax Battler - A Legend of Golden Axe (USA, Europe).zip",
    "Crystal Warriors (USA, Europe).zip",
    "Defenders of Oasis (USA, Europe).zip",
    "Mega Man (USA, Europe).zip",
    "Tails Adventure (USA, Europe).zip",
    "Land of Illusion Starring Mickey Mouse (USA, Europe).zip",
    "Dragon Crystal (USA, Europe).zip",
    "Ristar (USA, Europe).zip",
    "Streets of Rage 2 (USA, Europe).zip",
    "Gunstar Heroes (Japan).zip",
    "Virtua Fighter Animation (USA, Europe).zip",
    "Mortal Kombat II (USA, Europe).zip",
    "Baku Baku Animal (USA, Europe).zip",
    "Star Wars (USA, Europe).zip",
    "Power Strike II (Europe).zip",
    "Coca-Cola Kid (Japan).zip",
)

# ─── TurboGrafx-16 / PC Engine ──────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/pce",
    f"{NI}/NEC%20-%20PC%20Engine%20-%20TurboGrafx-16",
    "Bonk's Adventure (USA).zip",
    "Blazing Lazers (USA).zip",
    "R-Type (USA).zip",
    "Dungeon Explorer (USA).zip",
    "Military Madness (USA).zip",
    "Air Zonk (USA).zip",
    "Soldier Blade (USA).zip",
    "Alien Crush (USA).zip",
    "Devil's Crush (USA).zip",
    "Splatterhouse (USA).zip",
    "Legendary Axe, The (USA).zip",
    "Jackie Chan's Action Kung Fu (USA).zip",
    "Ninja Spirit (USA).zip",
    "New Adventure Island (USA).zip",
    "Galaga '90 (USA).zip",
    "Bomberman '93 (USA).zip",
    "Bomberman '94 (Japan).zip",
    "Keith Courage in Alpha Zones (USA).zip",
    "Dragon's Curse (USA).zip",
    "Neutopia (USA).zip",
    "Neutopia II (USA).zip",
    "Parasol Stars - The Story of Bubble Bobble III (USA).zip",
    "Psychosis (USA).zip",
    "Power Golf (USA).zip",
    "Pac-Land (USA).zip",
)

# ─── ATARI 2600 ─────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/atari2600",
    f"{NI}/Atari%20-%20Atari%202600",
    "Pitfall! (USA).zip",
    "River Raid (USA).zip",
    "Space Invaders (USA).zip",
    "Asteroids (USA).zip",
    "Missile Command (USA).zip",
    "Adventure (USA).zip",
    "Yars' Revenge (USA).zip",
    "Breakout (USA).zip",
    "Frogger (USA).zip",
    "Jungle Hunt (USA).zip",
    "Keystone Kapers (USA).zip",
    "Defender (USA).zip",
    "Pitfall II - Lost Caverns (USA).zip",
    "Enduro (USA).zip",
    "Demon Attack (USA).zip",
    "Haunted House (USA).zip",
    "Phoenix (USA).zip",
    "Berzerk (USA).zip",
    "Centipede (USA).zip",
    "Kaboom! (USA).zip",
    "H.E.R.O. (USA).zip",
    "Combat (USA).zip",
    "Megamania (USA).zip",
    "Activision Decathlon, The (USA).zip",
    "Solaris (USA).zip",
)

# ─── ATARI LYNX ─────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/lynx",
    f"{NI}/Atari%20-%20Atari%20Lynx%20(LNX)",
    "Blue Lightning (USA, Europe).zip",
    "Klax (USA).zip",
    "Chip's Challenge (USA, Europe).zip",
    "Gates of Zendocon (USA).zip",
    "Ninja Gaiden (USA, Europe).zip",
    "Rampart (USA).zip",
    "Joust (USA, Europe).zip",
    "Crystal Mines II (USA).zip",
    "Electrocop (USA, Europe).zip",
    "Pinball Jam (USA).zip",
    "Scrapyard Dog (USA, Europe).zip",
    "Todd's Adventures in Slime World (USA, Europe).zip",
    "Batman Returns (USA).zip",
    "Rygar (USA).zip",
    "Ms. Pac-Man (USA).zip",
    "Pac-Land (USA, Europe).zip",
    "California Games (USA, Europe).zip",
    "Awesome Golf (USA).zip",
    "Viking Child (USA, Europe).zip",
    "Dracula the Undead (USA, Europe).zip",
    "Eye of the Beholder (USA).zip",
    "Shadow of the Beast (USA, Europe).zip",
    "Warbirds (USA, Europe).zip",
    "Road Riot 4WD (USA).zip",
    "Checkered Flag (USA).zip",
)

# ─── NEO GEO POCKET COLOR ───────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/ngp",
    f"{NI}/SNK%20-%20NeoGeo%20Pocket%20Color",
    "Metal Slug - 1st Mission (USA, Europe).zip",
    "Metal Slug - 2nd Mission (USA, Europe).zip",
    "Samurai Shodown! 2 (USA, Europe).zip",
    "King of Fighters R-2, The (USA, Europe).zip",
    "SNK vs. Capcom - Match of the Millennium (USA, Europe).zip",
    "Sonic the Hedgehog Pocket Adventure (USA, Europe).zip",
    "Faselei! (USA, Europe).zip",
    "Dark Arms - Beast Buster 1999 (USA, Europe).zip",
    "SNK vs. Capcom - Card Fighters' Clash - Capcom Version! (USA).zip",
    "Last Blade, The - Beyond the Destiny (USA, Europe).zip",
    "Neo Turf Masters (USA, Europe).zip",
    "Biomotor Unitron (USA).zip",
    "Puzzle Bobble Mini (USA, Europe).zip",
    "Baseball Stars Color (USA, Europe).zip",
    "Big Bang Pro Wrestling (USA, Europe).zip",
    "Gals Fighters (Japan).zip",
    "Dive Alert - Becky's Version (USA, Europe).zip",
    "Cool Cool Jam (USA, Europe).zip",
)

# ─── WONDERSWAN COLOR ───────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/ws",
    f"{NI}/Bandai%20-%20WonderSwan%20Color",
    "Final Fantasy (Japan).zip",
    "Final Fantasy II (Japan).zip",
    "Final Fantasy IV (Japan).zip",
    "Makaimura for WonderSwan (Japan).zip",
    "Guilty Gear Petit (Japan).zip",
    "Guilty Gear Petit 2 (Japan).zip",
    "Dicing Knight Period (Japan).zip",
    "Riviera (Japan).zip",
    "Judgement Silversword - Rebirth Edition (Japan).zip",
    "Rhyme Rider Kerorican (Japan).zip",
    "SD Gundam G Generation - Gather Beat (Japan).zip",
    "Rockman & Forte - Mirai Kara no Chousensha (Japan).zip",
    "One Piece - Grand Battle! Swan Colosseum (Japan).zip",
    "beatmania for WonderSwan (Japan).zip",
    "Pocket Fighter (Japan).zip",
    "Digital Monster - Anode & Cathode Tamer (Japan).zip",
)

# ─── ARCADE (MAME) + NEO GEO ────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/arcade", MA,
    "neogeo.zip",
    "sf2ce.zip",
    "ssf2t.zip",
    "mslug.zip",
    "mslug2.zip",
    "mslugx.zip",
    "mslug3.zip",
    "mslug4.zip",
    "mslug5.zip",
    "kof98.zip",
    "kof2002.zip",
    "garou.zip",
    "lastbld2.zip",
    "samsho2.zip",
    "pacman.zip",
    "dkong.zip",
    "galaga.zip",
    "1942.zip",
    "1943.zip",
    "dino.zip",
    "ssriders.zip",
    "tmnt.zip",
    "tmnt2.zip",
    "xmen.zip",
    "simpsons.zip",
    "nbajamte.zip",
    "gauntlet.zip",
    "outrun.zip",
    "bublbobl.zip",
    "rtype.zip",
    "blazstar.zip",
    "pulstar.zip",
    "wjammers.zip",
    "rbff2.zip",
    "wakuwak7.zip",
    "sengoku3.zip",
    "kof2003.zip",
)


# ─── NINTENDO 3DS (Layton + extras) ─────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/3ds",
    f"{NI}/Nintendo%20-%20Nintendo%203DS%20(Decrypted)",
    "Professor Layton and the Miracle Mask (Europe).zip",
    "Professor Layton and the Azran Legacy (Europe).zip",
    "Professor Layton vs. Phoenix Wright - Ace Attorney (Europe).zip",
    "Layton's Mystery Journey - Katrielle and the Millionaires' Conspiracy (Europe).zip",
)

# ─── SEGA SATURN ────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/saturn",
    f"{RD}/Sega%20-%20Saturn",
    "Panzer Dragoon Saga (USA) (Disc 1).zip",
    "Panzer Dragoon Saga (USA) (Disc 2).zip",
    "Panzer Dragoon Saga (USA) (Disc 3).zip",
    "Panzer Dragoon Saga (USA) (Disc 4).zip",
    "Guardian Heroes (USA).zip",
    "Radiant Silvergun (Japan).zip",
    "NiGHTS into Dreams (USA).zip",
    "Dragon Force (USA).zip",
    "Burning Rangers (USA).zip",
    "Shining Force III (USA).zip",
    "Virtua Fighter 2 (USA).zip",
    "Sega Rally Championship (USA).zip",
    "Saturn Bomberman (USA).zip",
    "Fighters Megamix (USA).zip",
    "Daytona USA (USA).zip",
    "X-Men vs. Street Fighter (USA).zip",
    "Street Fighter Alpha 2 (USA).zip",
    "Magic Knight Rayearth (USA).zip",
    "Albert Odyssey - Legend of Eldean (USA).zip",
    "Dungeons & Dragons Collection (Japan).zip",
    "Vampire Savior - The Lord of Vampire (Japan).zip",
    "Dead or Alive (Japan).zip",
    "Panzer Dragoon II Zwei (USA).zip",
    "Panzer Dragoon (USA).zip",
    "Clockwork Knight (USA).zip",
)

# ─── SEGA CD ────────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/segaCD",
    f"{RD}/Sega%20-%20Mega%20CD",
    "Sonic CD (USA).zip",
    "Snatcher (USA).zip",
    "Lunar - The Silver Star (USA).zip",
    "Lunar - Eternal Blue (USA).zip",
    "Popful Mail (USA).zip",
    "Shining Force CD (USA).zip",
    "Final Fight CD (USA).zip",
    "Batman Returns (USA).zip",
    "Earthworm Jim - Special Edition (USA).zip",
    "Silpheed (USA).zip",
    "Road Avenger (USA).zip",
    "Vay (USA).zip",
    "Dark Wizard (USA).zip",
    "Ecco the Dolphin (USA).zip",
    "ESPN Baseball Tonight (USA).zip",
)

# ─── SEGA 32X ───────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/sega32x",
    f"{NI}/Sega%20-%2032X",
    "Knuckles' Chaotix (USA).zip",
    "Virtua Fighter (USA).zip",
    "Doom (USA).zip",
    "Star Wars Arcade (USA).zip",
    "Mortal Kombat II (USA).zip",
    "Space Harrier (USA).zip",
    "After Burner Complete (Japan).zip",
    "Virtua Racing Deluxe (USA).zip",
    "Shadow Squadron (USA).zip",
    "Metal Head (USA).zip",
)

# ─── ATARI 7800 ─────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/atari7800",
    f"{NI}/Atari%20-%20Atari%207800",
    "Ms. Pac-Man (USA).zip",
    "Centipede (USA).zip",
    "Joust (USA).zip",
    "Asteroids (USA).zip",
    "Dig Dug (USA).zip",
    "Robotron - 2084 (USA).zip",
    "Food Fight (USA).zip",
    "Xevious (USA).zip",
    "Pole Position II (USA).zip",
    "Commando (USA).zip",
    "Double Dragon (USA).zip",
    "Karateka (USA).zip",
    "Ballblazer (USA).zip",
    "Galaga (USA).zip",
    "Donkey Kong (USA).zip",
    "Desert Falcon (USA).zip",
    "Midnight Mutants (USA).zip",
    "Ninja Golf (USA).zip",
    "One-on-One Basketball (USA).zip",
    "Tower Toppler (USA).zip",
)

# ─── TURBOGRAFX-CD / PC ENGINE CD ───────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/pce",
    f"{RD}/NEC%20-%20PC%20Engine%20CD%20%26%20TurboGrafx%20CD",
    "Ys Book I & II (USA).zip",
    "Gate of Thunder (USA).zip",
    "Lords of Thunder (USA).zip",
    "Castlevania - Rondo of Blood (Japan).zip",
    "Snatcher (Japan).zip",
    "Ys III - Wanderers from Ys (USA).zip",
    "Dungeon Explorer (USA).zip",
    "Neutopia (USA).zip",
    "Neutopia II (USA).zip",
    "Akumajo Dracula X - Chi no Rondo (Japan).zip",
    "Cotton - Fantastic Night Dreams (Japan).zip",
    "Sapphire (Japan).zip",
    "Spriggan (Japan).zip",
    "Valis III (Japan).zip",
)

# ─── PS1 BONUS ──────────────────────────────────────────────────────────────
ALL_TASKS += tasks(f"{NAS}/psx",
    f"{RD}/Sony%20-%20PlayStation",
    "Tactics Ogre - Let Us Cling Together (USA).zip",
    "Breath of Fire III (USA).zip",
    "Parasite Eve II (USA) (Disc 1).zip",
    "Parasite Eve II (USA) (Disc 2).zip",
    "Crash Team Racing (USA).zip",
    "Einhander (USA).zip",
    "Lunar - Silver Star Story Complete (USA) (Disc 1).zip",
    "Lunar - Silver Star Story Complete (USA) (Disc 2).zip",
    "Lunar 2 - Eternal Blue Complete (USA) (Disc 1).zip",
    "Lunar 2 - Eternal Blue Complete (USA) (Disc 2).zip",
    "Lunar 2 - Eternal Blue Complete (USA) (Disc 3).zip",
    "Dino Crisis 2 (USA).zip",
    "Vandal Hearts (USA).zip",
    "Vandal Hearts II (USA).zip",
    "Azure Dreams (USA).zip",
    "Breath of Fire IV (USA) (Disc 1).zip",
    "Breath of Fire IV (USA) (Disc 2).zip",
)

# ── Main ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    total  = len(ALL_TASKS)
    done   = 0
    failed = []

    print(f"\n{'='*60}")
    print(f"  RomM Downloader — {total} files, 26 platforms")
    print(f"  Target: {NAS}")
    print(f"  Workers: {MAX_WORKERS}  |  Fuzzy filename matching: ON")
    print(f"{'='*60}\n")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
        futures = {pool.submit(download_one, *t): t for t in ALL_TASKS}
        for fut in as_completed(futures):
            t  = futures[fut]
            ok = fut.result()
            done += 1
            if not ok:
                failed.append(t[2])
            if done % 25 == 0 or done == total:
                log(f"\n  ── Progress {done}/{total} ──\n")

    print(f"\n{'='*60}")
    print(f"  DONE — {total-len(failed)}/{total} succeeded")
    if failed:
        print(f"\n  Missed ({len(failed)}):")
        for f in failed:
            print(f"    {f}")
    print(f"{'='*60}\n")
