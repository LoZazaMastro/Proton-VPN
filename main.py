from __future__ import annotations

import asyncio
import base64
import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path

import decky

VERSION = "1.0.0"
COUNTRY_NAMES = {'AW': 'Aruba', 'AF': 'Afghanistan', 'AO': 'Angola', 'AI': 'Anguilla', 'AX': 'Åland Islands', 'AL': 'Albania', 'AD': 'Andorra', 'AE': 'United Arab Emirates', 'AR': 'Argentina', 'AM': 'Armenia', 'AS': 'American Samoa', 'AQ': 'Antarctica', 'TF': 'French Southern Territories', 'AG': 'Antigua and Barbuda', 'AU': 'Australia', 'AT': 'Austria', 'AZ': 'Azerbaijan', 'BI': 'Burundi', 'BE': 'Belgium', 'BJ': 'Benin', 'BQ': 'Bonaire, Sint Eustatius and Saba', 'BF': 'Burkina Faso', 'BD': 'Bangladesh', 'BG': 'Bulgaria', 'BH': 'Bahrain', 'BS': 'Bahamas', 'BA': 'Bosnia and Herzegovina', 'BL': 'Saint Barthélemy', 'BY': 'Belarus', 'BZ': 'Belize', 'BM': 'Bermuda', 'BO': 'Bolivia', 'BR': 'Brazil', 'BB': 'Barbados', 'BN': 'Brunei', 'BT': 'Bhutan', 'BV': 'Bouvet Island', 'BW': 'Botswana', 'CF': 'Central African Republic', 'CA': 'Canada', 'CC': 'Cocos (Keeling) Islands', 'CH': 'Switzerland', 'CL': 'Chile', 'CN': 'China', 'CI': 'Côte d’Ivoire', 'CM': 'Cameroon', 'CD': 'Congo - Kinshasa', 'CG': 'Congo', 'CK': 'Cook Islands', 'CO': 'Colombia', 'KM': 'Comoros', 'CV': 'Cabo Verde', 'CR': 'Costa Rica', 'CU': 'Cuba', 'CW': 'Curaçao', 'CX': 'Christmas Island', 'KY': 'Cayman Islands', 'CY': 'Cyprus', 'CZ': 'Czechia', 'DE': 'Germany', 'DJ': 'Djibouti', 'DM': 'Dominica', 'DK': 'Denmark', 'DO': 'Dominican Republic', 'DZ': 'Algeria', 'EC': 'Ecuador', 'EG': 'Egypt', 'ER': 'Eritrea', 'EH': 'Western Sahara', 'ES': 'Spain', 'EE': 'Estonia', 'ET': 'Ethiopia', 'FI': 'Finland', 'FJ': 'Fiji', 'FK': 'Falkland Islands (Malvinas)', 'FR': 'France', 'FO': 'Faroe Islands', 'FM': 'Micronesia, Federated States of', 'GA': 'Gabon', 'GB': 'United Kingdom', 'GE': 'Georgia', 'GG': 'Guernsey', 'GH': 'Ghana', 'GI': 'Gibraltar', 'GN': 'Guinea', 'GP': 'Guadeloupe', 'GM': 'Gambia', 'GW': 'Guinea-Bissau', 'GQ': 'Equatorial Guinea', 'GR': 'Greece', 'GD': 'Grenada', 'GL': 'Greenland', 'GT': 'Guatemala', 'GF': 'French Guiana', 'GU': 'Guam', 'GY': 'Guyana', 'HK': 'Hong Kong SAR China', 'HM': 'Heard Island and McDonald Islands', 'HN': 'Honduras', 'HR': 'Croatia', 'HT': 'Haiti', 'HU': 'Hungary', 'ID': 'Indonesia', 'IM': 'Isle of Man', 'IN': 'India', 'IO': 'British Indian Ocean Territory', 'IE': 'Ireland', 'IR': 'Iran, Islamic Republic of', 'IQ': 'Iraq', 'IS': 'Iceland', 'IL': 'Israel', 'IT': 'Italy', 'JM': 'Jamaica', 'JE': 'Jersey', 'JO': 'Jordan', 'JP': 'Japan', 'KZ': 'Kazakhstan', 'KE': 'Kenya', 'KG': 'Kyrgyzstan', 'KH': 'Cambodia', 'KI': 'Kiribati', 'KN': 'Saint Kitts and Nevis', 'KR': 'South Korea', 'KW': 'Kuwait', 'LA': 'Laos', 'LB': 'Lebanon', 'LR': 'Liberia', 'LY': 'Libya', 'LC': 'Saint Lucia', 'LI': 'Liechtenstein', 'LK': 'Sri Lanka', 'LS': 'Lesotho', 'LT': 'Lithuania', 'LU': 'Luxembourg', 'LV': 'Latvia', 'MO': 'Macao SAR China', 'MF': 'Saint Martin (French part)', 'MA': 'Morocco', 'MC': 'Monaco', 'MD': 'Moldova', 'MG': 'Madagascar', 'MV': 'Maldives', 'MX': 'Mexico', 'MH': 'Marshall Islands', 'MK': 'North Macedonia', 'ML': 'Mali', 'MT': 'Malta', 'MM': 'Myanmar (Burma)', 'ME': 'Montenegro', 'MN': 'Mongolia', 'MP': 'Northern Mariana Islands', 'MZ': 'Mozambique', 'MR': 'Mauritania', 'MS': 'Montserrat', 'MQ': 'Martinique', 'MU': 'Mauritius', 'MW': 'Malawi', 'MY': 'Malaysia', 'YT': 'Mayotte', 'NA': 'Namibia', 'NC': 'New Caledonia', 'NE': 'Niger', 'NF': 'Norfolk Island', 'NG': 'Nigeria', 'NI': 'Nicaragua', 'NU': 'Niue', 'NL': 'Netherlands', 'NO': 'Norway', 'NP': 'Nepal', 'NR': 'Nauru', 'NZ': 'New Zealand', 'OM': 'Oman', 'PK': 'Pakistan', 'PA': 'Panama', 'PN': 'Pitcairn', 'PE': 'Peru', 'PH': 'Philippines', 'PW': 'Palau', 'PG': 'Papua New Guinea', 'PL': 'Poland', 'PR': 'Puerto Rico', 'KP': "Korea, Democratic People's Republic of", 'PT': 'Portugal', 'PY': 'Paraguay', 'PS': 'Palestinian Territories', 'PF': 'French Polynesia', 'QA': 'Qatar', 'RE': 'Réunion', 'RO': 'Romania', 'RU': 'Russia', 'RW': 'Rwanda', 'SA': 'Saudi Arabia', 'SD': 'Sudan', 'SN': 'Senegal', 'SG': 'Singapore', 'GS': 'South Georgia and the South Sandwich Islands', 'SH': 'Saint Helena, Ascension and Tristan da Cunha', 'SJ': 'Svalbard and Jan Mayen', 'SB': 'Solomon Islands', 'SL': 'Sierra Leone', 'SV': 'El Salvador', 'SM': 'San Marino', 'SO': 'Somalia', 'PM': 'Saint Pierre and Miquelon', 'RS': 'Serbia', 'SS': 'South Sudan', 'ST': 'Sao Tome and Principe', 'SR': 'Suriname', 'SK': 'Slovakia', 'SI': 'Slovenia', 'SE': 'Sweden', 'SZ': 'Eswatini', 'SX': 'Sint Maarten (Dutch part)', 'SC': 'Seychelles', 'SY': 'Syrian Arab Republic', 'TC': 'Turks and Caicos Islands', 'TD': 'Chad', 'TG': 'Togo', 'TH': 'Thailand', 'TJ': 'Tajikistan', 'TK': 'Tokelau', 'TM': 'Turkmenistan', 'TL': 'Timor-Leste', 'TO': 'Tonga', 'TT': 'Trinidad and Tobago', 'TN': 'Tunisia', 'TR': 'Türkiye', 'TV': 'Tuvalu', 'TW': 'Taiwan', 'TZ': 'Tanzania', 'UG': 'Uganda', 'UA': 'Ukraine', 'UM': 'United States Minor Outlying Islands', 'UY': 'Uruguay', 'US': 'United States', 'UZ': 'Uzbekistan', 'VA': 'Vatican City', 'VC': 'Saint Vincent and the Grenadines', 'VE': 'Venezuela', 'VG': 'Virgin Islands, British', 'VI': 'Virgin Islands, U.S.', 'VN': 'Vietnam', 'VU': 'Vanuatu', 'WF': 'Wallis and Futuna', 'WS': 'Samoa', 'YE': 'Yemen', 'ZA': 'South Africa', 'ZM': 'Zambia', 'ZW': 'Zimbabwe', 'XK': 'Kosovo'}
FALLBACK_CODES = ['AF', 'AL', 'DZ', 'AD', 'AO', 'AR', 'AM', 'AU', 'AT', 'AZ', 'BH', 'BD', 'BY', 'BE', 'BT', 'BO', 'BA', 'BR', 'BN', 'BG', 'KH', 'CM', 'CA', 'TD', 'CL', 'CO', 'KM', 'CD', 'CR', 'HR', 'CU', 'CY', 'CZ', 'CI', 'DK', 'DO', 'EC', 'EG', 'SV', 'ER', 'EE', 'ET', 'FI', 'FR', 'GA', 'GE', 'DE', 'GH', 'GR', 'GL', 'GT', 'GN', 'HT', 'HN', 'HK', 'HU', 'IS', 'IN', 'ID', 'IQ', 'IE', 'IL', 'IT', 'JM', 'JP', 'JO', 'KZ', 'KE', 'XK', 'KW', 'KG', 'LA', 'LV', 'LB', 'LY', 'LI', 'LT', 'LU', 'MO', 'MY', 'MT', 'MR', 'MU', 'MX', 'MD', 'MC', 'MN', 'ME', 'MA', 'MZ', 'MM', 'NP', 'NL', 'NZ', 'NI', 'NE', 'NG', 'NO', 'OM', 'PK', 'PA', 'PG', 'PY', 'PE', 'PH', 'PL', 'PT', 'PR', 'QA', 'RO', 'RU', 'RW', 'SA', 'SN', 'RS', 'SG', 'SK', 'SI', 'ZA', 'KR', 'ES', 'LK', 'SD', 'SE', 'CH', 'SY', 'TW', 'TZ', 'TH', 'TL', 'TG', 'TT', 'TN', 'TR', 'TM', 'UG', 'UA', 'AE', 'GB', 'US', 'UY', 'UZ', 'VE', 'VN', 'YE', 'ZM', 'ZW']

class Plugin:
    def __init__(self):
        self._plugin_dir = Path(__file__).resolve().parent
        settings_dir = Path(getattr(decky, "DECKY_PLUGIN_SETTINGS_DIR", self._plugin_dir))
        self._settings_file = settings_dir / "proton_vpn_qam.json"
        self._last_country = "IT"
        self._country_cache = []
        self._flag_cache = {}
        self._helper_lock = threading.Lock()
        self._operation_lock = asyncio.Lock()
        self._active_country = ""
        self._last_connect_code = ""
        self._last_connect_at = 0.0
        self._recent_countries = []
        self._load_settings()

    def _load_settings(self):
        try:
            data = json.loads(self._settings_file.read_text(encoding="utf-8"))
            code = str(data.get("last_country", "IT")).upper()
            if len(code) == 2:
                self._last_country = code
            active = str(data.get("active_country", "")).upper()
            if len(active) == 2:
                self._active_country = active
            recent = data.get("recent_countries", [])
            if isinstance(recent, list):
                seen = set()
                clean = []
                for item in recent:
                    rc = str(item or "").upper()
                    if len(rc) == 2 and rc in FALLBACK_CODES and rc not in seen:
                        clean.append(rc)
                        seen.add(rc)
                    if len(clean) >= 6:
                        break
                self._recent_countries = clean
        except Exception:
            pass

    def _save_settings(self):
        try:
            self._settings_file.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "last_country": self._last_country,
                "active_country": self._active_country,
                "recent_countries": self._recent_countries[:6],
            }
            self._settings_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        except Exception as exc:
            decky.logger.warning(f"Proton VPN: unable to save settings: {exc}")

    def _countries(self):
        if self._country_cache:
            return self._country_cache
        # Proton's logical-server endpoint requires authenticated API access.
        # Keep the installer self-contained and deterministic instead of issuing a request that returns 401.
        codes = FALLBACK_CODES
        out=[]
        for code in codes:
            name = COUNTRY_NAMES.get(code, code)
            out.append({"code": code, "name": name})
        out.sort(key=lambda x: x["name"].casefold())
        self._country_cache = out
        return out

    def _powershell(self):
        candidates = ["powershell.exe", "pwsh.exe"]
        for exe in candidates:
            try:
                subprocess.run([exe, "-NoProfile", "-Command", "$PSVersionTable.PSVersion.Major"], capture_output=True, timeout=2, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
                return exe
            except Exception:
                continue
        return "powershell.exe"

    def _run_helper(self, action: str, country_code: str = ""):
        # Serialize process/service diagnostics and future IPC calls so Decky never races helper invocations.
        with self._helper_lock:
            ps1 = self._plugin_dir / "helpers" / "proton_control.ps1"
            cmd=[self._powershell(), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(ps1), "-Action", action]
            if country_code:
                cmd += ["-CountryCode", country_code]
            flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            decky.logger.info(f"Proton VPN: helper start action={action} country={country_code or '-'}")
            try:
                proc = subprocess.run(cmd, capture_output=True, text=True, timeout=40, creationflags=flags)
            except subprocess.TimeoutExpired as exc:
                trace = exc.stderr or exc.stdout or ""
                if isinstance(trace, bytes):
                    trace = trace.decode("utf-8", errors="replace")
                trace = str(trace).strip().replace("\r", " ").replace("\n", " | ")
                decky.logger.error(
                    f"Proton VPN: helper timeout action={action} country={country_code or '-'}"
                    + (f" trace={trace[-900:]}" if trace else "")
                )
                return {"ok": False, "message": "Timeout durante il controllo del processo Proton VPN.", "stage": "timeout"}
            except Exception as exc:
                decky.logger.error(f"Proton VPN: helper launch failed action={action}: {exc}")
                return {"ok": False, "message": str(exc), "stage": "launch"}
            stdout=(proc.stdout or "").strip()
            stderr=(proc.stderr or "").strip()
            candidate = stdout.splitlines()[-1] if stdout else ""
            try:
                data=json.loads(candidate)
            except Exception:
                data={"ok": False, "message": stderr or stdout or f"PowerShell exited with code {proc.returncode}", "stage": "parse"}
            if proc.returncode != 0 and data.get("ok", True):
                data={"ok": False, "message": stderr or data.get("message") or f"PowerShell exited with code {proc.returncode}", "stage": data.get("stage", "exit")}
            decky.logger.info(
                f"Proton VPN: helper done action={action} country={country_code or '-'} "
                f"rc={proc.returncode} ok={bool(data.get('ok'))} connected={bool(data.get('connected'))} "
                f"stage={data.get('stage', '')} message={data.get('message', '')}"
            )
            if stderr:
                decky.logger.info(f"Proton VPN: helper trace: {stderr[-7000:].replace(chr(10), ' | ')}")
            return data

    async def get_countries(self):
        return await asyncio.to_thread(self._countries)

    async def get_flag(self, country_code: str):
        code = str(country_code or "").upper()
        if code not in {c["code"] for c in self._countries()}:
            return ""
        cached = self._flag_cache.get(code)
        if cached:
            return cached
        path = self._plugin_dir / "assets" / "flags" / f"{code}.png"
        try:
            raw = await asyncio.to_thread(path.read_bytes)
            value = "data:image/png;base64," + base64.b64encode(raw).decode("ascii")
            self._flag_cache[code] = value
            return value
        except Exception as exc:
            decky.logger.warning(f"Proton VPN: unable to load flag {code}: {exc}")
            return ""

    def _record_recent_country(self, code: str) -> None:
        normalized = str(code or "").upper()
        if len(normalized) != 2 or normalized not in FALLBACK_CODES:
            return
        self._recent_countries = [c for c in self._recent_countries if c != normalized]
        self._recent_countries.insert(0, normalized)
        self._recent_countries = self._recent_countries[:6]

    def _country_name(self, code: str) -> str:
        return COUNTRY_NAMES.get(str(code or '').upper(), str(code or '').upper())

    def _fast_status_from_client_log(self):
        """Read Proton's own latest connection state without starting PowerShell."""
        try:
            local = os.environ.get("LOCALAPPDATA", "")
            if not local:
                return None
            log_dir = Path(local) / "Proton" / "Proton VPN" / "Logs"
            if not log_dir.is_dir():
                return None
            candidates = [p for p in log_dir.iterdir() if p.is_file() and re.search(r"client.*\.(?:txt|log)$", p.name, re.I)]
            if not candidates:
                return None
            path = max(candidates, key=lambda item: item.stat().st_mtime_ns)
            size = path.stat().st_size
            if size <= 0:
                return None
            take = min(size, 262144)
            with path.open("rb") as fh:
                fh.seek(size - take)
                text = fh.read(take).decode("utf-8", errors="replace")
            for line in reversed(text.splitlines()):
                if re.search(r"\[CONNECTION_PROCESS\].*Status updated to Disconnected", line, re.I):
                    return {"ok": True, "connected": False, "country_code": "", "stage": "status-fast-python-log", "message": "Proton VPN risulta disconnessa."}
                if re.search(r"\[CONNECTION_PROCESS\].*Status updated to Connected", line, re.I):
                    match = re.search(r"Connected to server\s+([A-Z]{2})(?=[#\-\s])", line, re.I)
                    country = match.group(1).upper() if match else ""
                    return {
                        "ok": True,
                        "connected": True,
                        "country_code": country,
                        "stage": "status-fast-python-log",
                        "message": f"Proton VPN risulta connessa a {country}." if country else "Proton VPN risulta connessa.",
                    }
        except Exception as exc:
            decky.logger.debug(f"Proton VPN: fast log status unavailable: {exc}")
        return None

    def _enrich_result_country(self, result: dict, prefer_selected: bool = False) -> dict:
        result = dict(result or {})
        active = str(result.get("country_code") or "").upper()
        if result.get("connected"):
            if len(active) != 2 and len(self._active_country) == 2:
                active = self._active_country
            elif len(active) != 2 and prefer_selected and len(self._last_country) == 2:
                active = self._last_country
        if len(active) == 2:
            result["country_code"] = active
            result["country_name"] = self._country_name(active)
        else:
            result["country_code"] = ""
            result["country_name"] = ""
        result["last_country"] = self._last_country
        result["recent_countries"] = list(self._recent_countries[:6])
        return result

    async def set_country(self, country_code: str):
        code = str(country_code or "").upper()
        valid = {c["code"] for c in self._countries()}
        if code not in valid:
            return {"ok": False, "last_country": self._last_country}
        self._last_country = code
        self._save_settings()
        return {"ok": True, "last_country": self._last_country}

    async def get_status(self):
        fast = await asyncio.to_thread(self._fast_status_from_client_log)
        if fast is not None:
            result = self._enrich_result_country(fast)
        elif self._operation_lock.locked():
            result = self._enrich_result_country({
                "ok": True,
                "connected": bool(self._active_country),
                "country_code": self._active_country,
                "message": "Operazione Proton VPN in corso.",
                "stage": "operation-in-progress",
            })
        else:
            result = await asyncio.to_thread(self._run_helper, "status", self._last_country)
            result = self._enrich_result_country(result)
        active = str(result.get("country_code") or "").upper()
        if result.get("connected"):
            if len(active) == 2:
                changed = active != self._active_country
                self._active_country = active
                self._last_country = active
                if changed or active not in self._recent_countries:
                    self._record_recent_country(active)
                self._save_settings()
        else:
            self._active_country = ""
            self._save_settings()
        result["last_country"] = self._last_country
        return result

    async def connect_country(self, country_code: str):
        code = str(country_code or "").upper()
        valid = {c["code"] for c in self._countries()}
        if code not in valid:
            return {"ok": False, "message": "Paese non disponibile nella lista Proton VPN.", "last_country": self._last_country}

        async with self._operation_lock:
            now = time.monotonic()
            decky.logger.info(f"Proton VPN: connect requested country={code}")
            self._last_country = code
            self._save_settings()

            if self._last_connect_code == code and (now - self._last_connect_at) < 5.0 and self._active_country == code:
                self._record_recent_country(code)
                self._save_settings()
                return {
                    "ok": True,
                    "connected": True,
                    "country_code": code,
                    "country_name": self._country_name(code),
                    "last_country": code,
                    "message": f"Proton VPN è già connessa a {code}.",
                    "stage": "duplicate-connect-suppressed",
                    "recent_countries": list(self._recent_countries[:6]),
                }

            # The PowerShell connect action already verifies the current route/country and
            # returns a no-op when it is already on the requested country. R16.1 ran a
            # second status helper here first, adding latency and creating another window
            # in which the QAM dropdown could be overwritten by an older status result.
            if self._active_country == code:
                self._record_recent_country(code)
                self._last_connect_code = code
                self._last_connect_at = time.monotonic()
                return {
                    "ok": True,
                    "connected": True,
                    "country_code": code,
                    "country_name": self._country_name(code),
                    "last_country": code,
                    "message": f"Proton VPN è già connessa a {code}.",
                    "stage": "cached-already-connected-same-country",
                    "recent_countries": list(self._recent_countries[:6]),
                }

            result = await asyncio.to_thread(self._run_helper, "connect", code)
            result = self._enrich_result_country(result, True)
            active = str(result.get("country_code") or "").upper()

            if result.get("ok") and result.get("connected"):
                if len(active) == 2 and active != code:
                    result["ok"] = False
                    result["stage"] = "country-mismatch"
                    result["message"] = f"Proton VPN risulta connessa a {active}, non a {code}."
                    self._active_country = active
                    self._last_country = active
                else:
                    active = active if len(active) == 2 else code
                    self._active_country = active
                    self._last_country = active
                    result["country_code"] = active
                    result["country_name"] = self._country_name(active)
                    self._last_connect_code = active
                    self._last_connect_at = time.monotonic()
                    self._record_recent_country(active)
                self._save_settings()
            elif result.get("connected") and len(active) == 2:
                self._active_country = active
                self._last_country = active
                self._save_settings()

            result["last_country"] = self._last_country
            result["recent_countries"] = list(self._recent_countries[:6])
            return result

    async def disconnect(self):
        async with self._operation_lock:
            decky.logger.info(f"Proton VPN: disconnect requested last_country={self._last_country}")
            result = await asyncio.to_thread(self._run_helper, "disconnect", self._last_country)
            result = self._enrich_result_country(result)
            if not result.get("connected"):
                self._active_country = ""
                result["country_code"] = ""
                result["country_name"] = ""
                self._save_settings()
            result["last_country"] = self._last_country
            result["recent_countries"] = list(self._recent_countries[:6])
            return result

    async def _main(self):
        decky.logger.info("Proton VPN 1.0.0 R16.6 loaded (automatic Steam language / 31 full-platform translations / localized country names)")

    async def _unload(self):
        decky.logger.info("Proton VPN unloaded")
