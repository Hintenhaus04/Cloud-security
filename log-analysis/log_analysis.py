"""Opdracht 6.5: inlogpogingen in Linux_2k.log analyseren met machine learning.

Grafiek 1: aantal inlogpogingen per uur op een tijdlijn, met de afwijkende uren (IsolationForest) in rood.
Grafiek 2: per bron-IP/host het aantal inlogpogingen, met de afwijkende bronnen (IsolationForest) in rood.

Een inlogpoging is een PAM-regel "authentication failure" (mislukt) of "session opened" van sshd/login (gelukt).
FTP-regels "connection from" zijn verbindingen en geen inlogpogingen; die tellen we apart.

De datums in de aangeleverde log zijn geanonimiseerd (alles staat in "Jan", met dagen die niet oplopen).
De regels staan wel op volgorde, dus het script maakt de tijdlijn op basis van de volgorde van de uurblokken
en gebruikt de datum alleen als label.

Gebruik:
    pip install pandas scikit-learn matplotlib
    python log_analysis.py [pad/naar/Linux_2k.log]
"""

import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
from sklearn.ensemble import IsolationForest

LOG_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("Linux_2k.log")
OUT_DIR = Path(__file__).parent

LINE = re.compile(r"^(?P<dag>\w{3}\s+\d+)\s(?P<uur>\d{2}):\d{2}:\d{2}\s\S+\s(?P<proc>[\w()]+)\[\d+\]:\s(?P<msg>.*)$")
RHOST = re.compile(r"rhost=(?P<host>\S+)")
USER = re.compile(r"\buser=(?P<user>\S+)")
SESSION_OPENED = re.compile(r"session opened for user (?P<user>\S+)")
FTP_CONNECT = re.compile(r"connection from (?P<host>\S+)")


def parse(path: Path) -> tuple[pd.DataFrame, int]:
    """Haal alle inlogpogingen uit de log. Geeft ook het aantal FTP-verbindingen terug."""
    rows, ftp, block, last_key = [], 0, -1, None
    for raw in path.read_text(errors="replace").splitlines():
        m = LINE.match(raw.strip())
        if not m:
            continue
        day, hour = " ".join(m["dag"].split()), int(m["uur"])
        # Nieuw uurblok zodra dag of uur verandert (de log is chronologisch)
        if (day, hour) != last_key:
            block, last_key = block + 1, (day, hour)
        label = f"{day} {hour:02d}:00"
        service, msg = m["proc"].split("(")[0], m["msg"]

        if "authentication failure" in msg:
            host, user = RHOST.search(msg), USER.search(msg)
            rows.append((block, label, service, "mislukt", host["host"] if host else "onbekend", user["user"] if user else ""))
        elif service in ("sshd", "login") and (s := SESSION_OPENED.search(msg)):
            rows.append((block, label, service, "gelukt", "onbekend", s["user"]))
        elif service == "ftpd" and FTP_CONNECT.search(msg):
            ftp += 1

    df = pd.DataFrame(rows, columns=["blok", "uur", "dienst", "soort", "bron", "gebruiker"])
    return df, ftp


def hourly_anomalies(df: pd.DataFrame) -> pd.DataFrame:
    """Tel pogingen per uurblok en laat IsolationForest de uitschieters aanwijzen."""
    per_hour = df.groupby(["blok", "uur"]).size().rename("pogingen").reset_index().set_index("blok")
    model = IsolationForest(n_estimators=200, contamination=0.03, random_state=42)
    per_hour["afwijkend"] = model.fit_predict(per_hour[["pogingen"]]) == -1
    # Alleen uitschieters naar boven zijn verdacht, een rustig uur niet
    per_hour.loc[per_hour["pogingen"] <= per_hour["pogingen"].median(), "afwijkend"] = False
    return per_hour


def source_anomalies(df: pd.DataFrame) -> pd.DataFrame:
    """Bouw kenmerken per bron (IP/host) en laat IsolationForest afwijkende bronnen vinden."""
    known = df[df["bron"] != "onbekend"]
    per_hour = known.groupby(["bron", "blok"]).size()
    features = pd.DataFrame(
        {
            "pogingen": known.groupby("bron").size(),
            "max_per_uur": per_hour.groupby(level=0).max(),
            "actieve_uren": per_hour.groupby(level=0).size(),
            "gebruikers": known.groupby("bron")["gebruiker"].nunique(),
        }
    )
    features["pogingen_per_uur"] = features["pogingen"] / features["actieve_uren"]

    model = IsolationForest(n_estimators=200, contamination=0.05, random_state=42)
    features["afwijkend"] = model.fit_predict(features) == -1
    features["score"] = -model.score_samples(features.drop(columns="afwijkend"))  # hoger = vreemder
    return features.sort_values("pogingen", ascending=False)


def plot_hourly(per_hour: pd.DataFrame, path: Path) -> None:
    fig, ax = plt.subplots(figsize=(14, 5))
    colors = ["#E45756" if a else "#4C78A8" for a in per_hour["afwijkend"]]
    ax.bar(range(len(per_hour)), per_hour["pogingen"], color=colors, width=0.9)
    for x, (_, row) in enumerate(per_hour.iterrows()):
        if row["afwijkend"]:
            ax.annotate(f'{row["uur"]}\n{row["pogingen"]}', (x, row["pogingen"]), textcoords="offset points",
                        xytext=(0, 4), ha="center", fontsize=8, color="#B22222")
    step = max(1, len(per_hour) // 15)
    ax.set_xticks(range(0, len(per_hour), step))
    ax.set_xticklabels(per_hour["uur"].iloc[::step], rotation=45, ha="right", fontsize=8)
    ax.set_title("Inlogpogingen per uur (rood = afwijkend volgens IsolationForest)")
    ax.set_xlabel("Uur (in volgorde van de log)")
    ax.set_ylabel("Aantal pogingen")
    ax.margins(y=0.15)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def plot_sources(features: pd.DataFrame, path: Path, top: int = 20) -> None:
    data = features.head(top).iloc[::-1]
    colors = ["#E45756" if a else "#4C78A8" for a in data["afwijkend"]]
    fig, ax = plt.subplots(figsize=(11, 7))
    ax.barh(data.index, data["pogingen"], color=colors)
    for y, (count, peak) in enumerate(zip(data["pogingen"], data["max_per_uur"])):
        ax.text(count + 0.5, y, f"max {int(peak)}/uur", va="center", fontsize=8)
    ax.set_title(f"Top {top} bronnen van inlogpogingen (rood = afwijkend volgens IsolationForest)")
    ax.set_xlabel("Aantal inlogpogingen")
    ax.margins(x=0.12)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def main() -> None:
    df, ftp = parse(LOG_FILE)
    print(f"{len(df)} inlogpogingen gevonden ({ftp} FTP-verbindingen niet meegeteld)")
    print(df["soort"].value_counts().to_string(), "\n")

    per_hour = hourly_anomalies(df)
    print("Afwijkende uren:")
    print(per_hour[per_hour["afwijkend"]].sort_values("pogingen", ascending=False).to_string(), "\n")

    features = source_anomalies(df)
    print("Afwijkende bronnen:")
    print(features[features["afwijkend"]].sort_values("score", ascending=False).round(2).to_string())

    plot_hourly(per_hour, OUT_DIR / "inlogpogingen_per_uur.png")
    plot_sources(features, OUT_DIR / "afwijkende_bronnen.png")
    features.round(2).to_csv(OUT_DIR / "bronnen_met_score.csv")
    print(f"\nGrafieken opgeslagen in {OUT_DIR}")


if __name__ == "__main__":
    main()
