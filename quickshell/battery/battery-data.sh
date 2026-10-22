#!/usr/bin/env bash
# ~/.config/quickshell/battery/battery-data.sh
#
# Batarya menusune JSON basar. QML sunlari bekliyor:
#   cap, status, watt, hours, health, temp, profile, gfx, apps[{name,w,r}]
# Ek alanlar: ac (adaptor takili mi), wattSrc (watt nereden geldi)
#
# Lenovo koruma modunda pil ne dolar ne bosalir, power_now 0 gelir.
# O durumda watt olarak SISTEM tuketimini (CPU RAPL + GPU) veriyoruz,
# yoksa menude hep "0.0 W" goruluyor.

export LC_ALL=C
PS_ROOT="${PS_ROOT:-/sys/class/power_supply}"
RAPL_F="${RAPL_F:-/sys/class/powercap/intel-rapl:0/energy_uj}"
PROFILE_F="${PROFILE_F:-/sys/firmware/acpi/platform_profile}"
SAMPLE="${BAT_SAMPLE:-0.35}"     # tek olcum penceresi
TOP_N="${BAT_TOP_N:-3}"

read1() { local v; { read -r v < "$1"; } 2>/dev/null && printf '%s' "$v"; }
num()   { [[ "${1:-}" =~ ^-?[0-9]+$ ]] && printf '%s' "${1#-}" || printf '0'; }

# ---------------- pil ve adaptor ----------------
BAT=""; AC=""
for d in "$PS_ROOT"/*; do
    [[ -e "$d/type" ]] || continue
    case "$(read1 "$d/type")" in
        Battery) [[ -z "$BAT" ]] && BAT="$d" ;;
        Mains)   [[ -z "$AC"  ]] && AC="$d"  ;;
    esac
done

CAP=0; STATUS="Unknown"; AC_ONLINE=0
if [[ -n "$BAT" ]]; then
    CAP=$(num "$(read1 "$BAT/capacity")")
    STATUS="$(read1 "$BAT/status")"
    [[ -z "$STATUS" ]] && STATUS="Unknown"
fi
[[ -n "$AC" ]] && AC_ONLINE=$(num "$(read1 "$AC/online")")

# ---------------- pil gucu (mikrowatt) ----------------
PWR_UW=0
if [[ -n "$BAT" && -r "$BAT/power_now" ]]; then
    PWR_UW=$(num "$(read1 "$BAT/power_now")")
elif [[ -n "$BAT" && -r "$BAT/current_now" && -r "$BAT/voltage_now" ]]; then
    CUR=$(num "$(read1 "$BAT/current_now")")
    VOL=$(num "$(read1 "$BAT/voltage_now")")
    PWR_UW=$(awk -v c="$CUR" -v v="$VOL" 'BEGIN{printf "%d", c*v/1000000}')
fi

# ---------------- enerji / saglik ----------------
E_NOW=0; E_FULL=0; E_DESIGN=0
if [[ -n "$BAT" && -r "$BAT/energy_now" ]]; then
    E_NOW=$(num "$(read1 "$BAT/energy_now")")
    E_FULL=$(num "$(read1 "$BAT/energy_full")")
    E_DESIGN=$(num "$(read1 "$BAT/energy_full_design")")
elif [[ -n "$BAT" && -r "$BAT/charge_now" ]]; then
    VOL=$(num "$(read1 "$BAT/voltage_now")")
    (( VOL == 0 )) && VOL=$(num "$(read1 "$BAT/voltage_min_design")")
    E_NOW=$(awk    -v a="$(num "$(read1 "$BAT/charge_now")")"         -v v="$VOL" 'BEGIN{printf "%d", a*v/1000000}')
    E_FULL=$(awk   -v a="$(num "$(read1 "$BAT/charge_full")")"        -v v="$VOL" 'BEGIN{printf "%d", a*v/1000000}')
    E_DESIGN=$(awk -v a="$(num "$(read1 "$BAT/charge_full_design")")" -v v="$VOL" 'BEGIN{printf "%d", a*v/1000000}')
fi

HEALTH=100
if (( E_DESIGN > 0 && E_FULL > 0 )); then
    HEALTH=$(awk -v f="$E_FULL" -v d="$E_DESIGN" 'BEGIN{printf "%d", (f/d)*100 + 0.5}')
fi

# ---------------- sicaklik ----------------
TEMP=0
if [[ -n "$BAT" && -r "$BAT/temp" ]]; then
    TEMP=$(awk -v t="$(num "$(read1 "$BAT/temp")")" 'BEGIN{printf "%d", t/10}')
fi
if (( TEMP <= 0 || TEMP > 120 )); then
    for z in /sys/class/thermal/thermal_zone*; do
        [[ -r "$z/type" ]] || continue
        case "$(read1 "$z/type")" in
            x86_pkg_temp|acpitz|coretemp)
                t=$(num "$(read1 "$z/temp")")
                if (( t > 1000 )); then TEMP=$(( t / 1000 )); else TEMP=$t; fi
                break ;;
        esac
    done
fi

# ---------------- TEK OLCUM PENCERESI ----------------
# RAPL enerjisi ve surec CPU tiklari ayni aralikta orneklenir.
proc_snapshot() {
    awk '
    FNR == 1 {
        op = index($0, "(")
        q  = index($0, ")")
        if (op == 0 || q == 0) next
        name = substr($0, op + 1, q - op - 1)
        n = split(substr($0, q + 2), a, " ")
        if (n < 13) next
        # PF_KTHREAD (0x00200000) -> cekirdek thread, uygulama degil (kworker, rcu_ vs.)
        if (int(a[7] / 2097152) % 2 == 1) next
        sum[name] += a[12] + a[13]          # utime + stime
    }
    END { for (k in sum) printf "%s\t%d\n", k, sum[k] }
    ' /proc/[0-9]*/stat 2>/dev/null
}

E1=0; [[ -r "$RAPL_F" ]] && E1=$(num "$(read1 "$RAPL_F")")
SNAP1=$(proc_snapshot)
sleep "$SAMPLE"
E2=0; [[ -r "$RAPL_F" ]] && E2=$(num "$(read1 "$RAPL_F")")
SNAP2=$(proc_snapshot)

# ---------------- watt ----------------
WATT=$(awk -v p="$PWR_UW" 'BEGIN{printf "%.1f", p/1000000}')
WATT_SRC="battery"

if awk -v w="$WATT" 'BEGIN{exit !(w < 0.5)}'; then
    CPU_W=0
    if (( E1 > 0 && E2 >= E1 )); then
        CPU_W=$(awk -v a="$E1" -v b="$E2" -v s="$SAMPLE" 'BEGIN{printf "%.2f", (b-a)/1000000/s}')
    fi
    GPU_W=0
    if command -v nvidia-smi >/dev/null 2>&1; then
        g=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)
        [[ "$g" =~ ^[0-9.]+$ ]] && GPU_W="$g"
    fi
    WATT=$(awk -v c="$CPU_W" -v g="$GPU_W" 'BEGIN{printf "%.1f", c+g}')
    WATT_SRC="system"
fi

# ---------------- kalan sure ----------------
HOURS=0
if (( PWR_UW > 100000 )); then
    case "$STATUS" in
        Discharging)
            HOURS=$(awk -v e="$E_NOW" -v p="$PWR_UW" 'BEGIN{printf "%.2f", e/p}') ;;
        Charging)
            HOURS=$(awk -v e="$E_NOW" -v f="$E_FULL" -v p="$PWR_UW" \
                    'BEGIN{d=f-e; if(d<0)d=0; printf "%.2f", d/p}') ;;
    esac
fi

# ---------------- profil / grafik modu ----------------
PROFILE="$(read1 "$PROFILE_F")"
[[ -z "$PROFILE" ]] && PROFILE="balanced"

GFX="Hibrit"
if [[ -d /sys/class/drm/card1-eDP-1 ]] && [[ ! -d /sys/module/i915 ]]; then
    GFX="dGPU"
fi

# ---------------- en cok tuketen uygulamalar ----------------
# Gercek per-process wattmetre yok; toplam gucu CPU payina gore dagitiyoruz.
APPS=$(printf '%s\n===\n%s\n' "$SNAP1" "$SNAP2" | awk -v tw="$WATT" -v topn="$TOP_N" '
    /^===$/ { second = 1; next }
    {
        i = index($0, "\t")
        if (i == 0) next
        k = substr($0, 1, i - 1)
        v = substr($0, i + 1) + 0
        if (second) b[k] = v; else a[k] = v
    }
    END {
        grand = 0
        for (k in b) {
            d = b[k] - (k in a ? a[k] : 0)
            if (d > 0) { delta[k] = d; grand += d }
        }
        if (grand <= 0) { printf "[]"; exit }

        printf "["
        out = 0
        for (round = 1; round <= topn; round++) {
            best = ""; bestv = 0
            for (k in delta) if (delta[k] > bestv) { bestv = delta[k]; best = k }
            if (best == "") break
            share = bestv / grand
            clean = best
            gsub(/["\\]/, "", clean)
            if (out) printf ","
            printf "{\"name\":\"%s\",\"w\":%.2f,\"r\":%.3f}", clean, share * tw, share
            out = 1
            delete delta[best]
        }
        printf "]"
    }')
[[ -z "$APPS" ]] && APPS="[]"

# ---------------- cikti ----------------
printf '{"cap":%s,"status":"%s","watt":%s,"hours":%s,"health":%s,"temp":%s,"profile":"%s","gfx":"%s","ac":%s,"wattSrc":"%s","apps":%s}\n' \
    "$CAP" "$STATUS" "$WATT" "$HOURS" "$HEALTH" "$TEMP" "$PROFILE" "$GFX" "$AC_ONLINE" "$WATT_SRC" "$APPS"
