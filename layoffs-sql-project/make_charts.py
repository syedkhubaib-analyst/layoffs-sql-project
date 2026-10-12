"""Regenerates the README charts from data/layoffs_cleaned.csv (output of the SQL pipeline)."""
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

df = pd.read_csv("data/layoffs_cleaned.csv", parse_dates=["date"])
OUT = "images/"
BLUE, GREY = "#1f5fa8", "#9aa5b1"
plt.rcParams.update({"font.size": 10, "axes.spines.top": False, "axes.spines.right": False})

# 1. Monthly layoffs + rolling total
m = df.dropna(subset=["date"]).set_index("date")["total_laid_off"].resample("MS").sum()
fig, ax = plt.subplots(figsize=(9, 4.2))
ax.bar(m.index, m.values, width=22, color=BLUE)
ax.set_ylabel("Employees laid off per month")
ax2 = ax.twinx()
ax2.plot(m.index, m.cumsum(), color="#d9822b", lw=2)
ax2.set_ylabel("Cumulative total"); ax2.spines["top"].set_visible(False)
ax.set_title("Layoffs peaked in Nov 2022 and Jan 2023 (2023 = Jan-Mar 6 only)")
fig.tight_layout(); fig.savefig(OUT + "monthly_layoffs.png", dpi=150); plt.close()

# 2. Top 10 companies
c = df.groupby("company")["total_laid_off"].sum().nlargest(10).sort_values()
fig, ax = plt.subplots(figsize=(8, 4.2))
ax.barh(c.index, c.values, color=BLUE)
for i, v in enumerate(c.values): ax.text(v + 150, i, f"{int(v):,}", va="center", fontsize=9)
ax.set_title("Top 10 companies by total layoffs"); ax.set_xlabel("Employees laid off")
fig.tight_layout(); fig.savefig(OUT + "top_companies.png", dpi=150); plt.close()

# 3. Industries
i = df.groupby("industry")["total_laid_off"].sum().nlargest(10).sort_values()
fig, ax = plt.subplots(figsize=(8, 4.2))
ax.barh(i.index, i.values, color=BLUE)
for k, v in enumerate(i.values): ax.text(v + 150, k, f"{int(v):,}", va="center", fontsize=9)
ax.set_title("Top 10 industries by total layoffs"); ax.set_xlabel("Employees laid off")
fig.tight_layout(); fig.savefig(OUT + "top_industries.png", dpi=150); plt.close()

# 4. Country share
co = df.groupby("country")["total_laid_off"].sum().nlargest(6).sort_values()
fig, ax = plt.subplots(figsize=(8, 3.6))
ax.barh(co.index, co.values, color=[GREY]*5 + [BLUE])
tot = df["total_laid_off"].sum()
for k, v in enumerate(co.values): ax.text(v + 1500, k, f"{int(v):,} ({v/tot:.0%})", va="center", fontsize=9)
ax.set_title("Top 6 countries by total layoffs"); ax.set_xlim(0, co.max()*1.25)
fig.tight_layout(); fig.savefig(OUT + "top_countries.png", dpi=150); plt.close()
print("ok")
