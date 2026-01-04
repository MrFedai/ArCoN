#!/bin/bash
# ArCoN - Ultimate Universal Linux Setup (Arch/Debian/Ubuntu)
# Global Standard, Optimized, Anonymized & Gaming Ready

# --- COLORS & UI ---
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}      ArCoN Ultimate Setup Wizard        ${NC}"
echo -e "${BLUE}=========================================${NC}"

# --- HELPER FUNCTIONS ---
# (Fonksiyonları en başa aldık ki Sector 0'da hata vermesin)
ask_step() {
    echo -ne "${YELLOW}>> $1? (y/n): ${NC}"
    read -r choice
    [[ "$choice" == [yY] || "$choice" == [yY][eE][sS] ]]
}

# --- PRE-FLIGHT CHECKS ---
echo -e "${YELLOW}[*] Running pre-flight checks...${NC}"

# 1. Check Internet Connection
if ! ping -c 1 google.com &> /dev/null && ! ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "${RED}[ERROR] No internet connection detected!${NC}"
    echo -e "${YELLOW}[TIP] Please check your network and try again.${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Internet connection: OK${NC}"

# 2. Check Disk Space (minimum 10GB free)
available_space=$(df / | tail -1 | awk '{print $4}')
required_space=$((10 * 1024 * 1024)) # 10GB in KB
if [ "$available_space" -lt "$required_space" ]; then
    echo -e "${RED}[ERROR] Insufficient disk space!${NC}"
    echo -e "${YELLOW}[INFO] Available: $(($available_space / 1024 / 1024))GB | Required: 10GB${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Disk space: OK ($(($available_space / 1024 / 1024))GB available)${NC}"

# 3. Check Sudo Privileges
if ! sudo -v &> /dev/null; then
    echo -e "${RED}[ERROR] This script requires sudo privileges!${NC}"
    echo -e "${YELLOW}[TIP] Run: sudo -v${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Sudo privileges: OK${NC}"

echo -e "${GREEN}[✓] Pre-flight checks passed!${NC}\n"

# --- LIVE USB DETECTION ---
if df -h / | grep -q "tmpfs\|overlay"; then
    echo -e "${RED}╔════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║        ⚠️  LIVE ENVIRONMENT DETECTED  ⚠️       ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}[WARNING] You are running from a Live USB/ISO!${NC}"
    
    if ! ask_step "Continue anyway (NOT RECOMMENDED)"; then
        echo -e "${BLUE}[*] Installation cancelled. Goodbye!${NC}"
        exit 0
    fi
    echo -e "${YELLOW}[!] Proceeding at your own risk...${NC}\n"
fi

# --- OS DETECTION ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    echo -e "${GREEN}>> Detected OS: $OS${NC}"
else
    echo -e "${RED}>> Error: OS not detected.${NC}"; exit 1
fi

# --- PACKAGE MANAGER SETTINGS ---
case "$OS" in
    arch)
        PKG_MGR="sudo pacman -S --noconfirm --needed"
        AUR_MGR="yay -S --noconfirm --needed"
        IS_ARCH=true ;;
    ubuntu|debian)
        PKG_MGR="sudo apt-get install -y"
        IS_ARCH=false; sudo apt-get update || { echo -e "${RED}[ERROR] apt update failed!${NC}"; exit 1; } ;;
    *) echo -e "${RED}>> Unsupported OS${NC}"; exit 1 ;;
esac

# ==============================================================================
# GLOBAL PACKAGE DEFINITIONS
# ==============================================================================

# 1. ESSENTIALS
declare -a PKG_ESSENTIALS=(
    "google-chrome" "man-db" "man-pages" "telegram-desktop" "localsend-bin"
    "code" "vim" "neovim" "git" 
    "riseup-vpn" "vlc" "planify" "flameshot" "timeshift"
    "btop" "fastfetch" "wget" "curl"
    "unzip" "zip" "ntfs-3g" "dosfstools"
)

# 2. MEDIA & OFFICE
declare -a PKG_MEDIA=(
    "libreoffice-fresh" "blender" "discord" "firefox" "gimp" "obsidian" "kdenlive" "inkscape"
    "audacity" "easyeffects" "losslesscut-bin" "upscayl-bin" "spotify" "obs-studio" "shortwave"
)

# 3. CYBER SECURITY
declare -a PKG_CYBER=(
    "nmap" "metasploit" "masscan" "wireshark-qt" "aircrack-ng" "burpsuite"
    "gobuster" "hashcat" "hydra" "john" "sqlmap" "nikto" "ghidra"
    "radare2" "bettercap" "exploitdb" "remmina" "freerdp"
)

# 4. REMOTE SUPPORT
declare -a PKG_REMOTE=(
    "anydesk-bin" "rustdesk-bin" "x11vnc" "openvpn" "wireguard-tools"
    "networkmanager-openvpn" "torbrowser-launcher" "proton-vpn-gtk-app"
)

# 5. POWER TOOLS & PRIVACY
declare -a PKG_POWER=(
    "onionshare" "metadata-cleaner" "virt-manager" "qemu-desktop" "ananicy-cpp"
    "bleachbit" "stacer" "pinokio" "stirling-pdf" "switcheroo" "converseen"
    "devtoys-bin" "clapgrep"
)


# ==============================================================================
# SECTOR 0: MAIN MENU & SMART FACTORY RESET (SAFE MODE)
# ==============================================================================

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              ArCoN MAIN OPERATIONS MENU              ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo -e "${BOLD}Select an operation mode:${NC}"
echo -e "  ${GREEN}1) START INSTALLATION${NC} (Normal Setup Wizard)"
echo -e "  ${RED}2) SMART FACTORY RESET${NC} (Clean Configs & Uninstall Apps)"
echo -e "  ${YELLOW}3) EXIT${NC}"

read -p "Select [1-3]: " main_choice

case $main_choice in
    1)
        echo -e "\n${BLUE}[*] Starting ArCoN Setup Wizard...${NC}"
        # Script buradan aşağıya (Normal kuruluma) devam eder...
        ;;
    2)
        echo -e "\n${RED}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║        ⚠️  SMART CLEANUP PROTOCOL (SAFE MODE) ⚠️    ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
        echo -e "${YELLOW}This mode scans your package lists and initiates cleanup.${NC}"
        
        if ask_step "${RED}START CLEANUP PROCESS? (Config backup included)${NC}"; then
            
            echo -ne "${RED}>> Type 'CLEAN' to confirm: ${NC}"
            read -r confirm_reset
            
            if [ "$confirm_reset" == "CLEAN" ]; then
                echo -e "\n${BLUE}[*] Analyzing Database & Creating Backup...${NC}"
                
                BACKUP_DIR="$HOME/arcon_backup_$(date +%s)"
                mkdir -p "$BACKUP_DIR"
                
                # Tüm hedef paketleri birleştir
                ALL_TARGETS=("${PKG_ESSENTIALS[@]}" "${PKG_MEDIA[@]}" "${PKG_CYBER[@]}" "${PKG_REMOTE[@]}" "${PKG_POWER[@]}")
                
                # pacs.txt varsa ekle
                if [ -f "pacs.txt" ]; then
                    while IFS= read -r line || [[ -n "$line" ]]; do
                        clean_line=$(echo "$line" | sed 's/#.*//' | xargs)
                        [ -n "$clean_line" ] && ALL_TARGETS+=("$clean_line")
                    done < pacs.txt
                fi

                # --- KRİTİK PAKET KORUMASI (WHITELIST) ---
                # Bu listedeki paketler ASLA SİLİNMEZ.
                PROTECTED_PKGS=(
                    # Sistem Çekirdeği
                    "base" "base-devel" "linux" "linux-firmware" "sudo" "pacman" "yay" "systemd" "systemd-libs" "glibc"
                    # Ağ Araçları
                    "networkmanager" "network-manager-applet" "wpa_supplicant" "wget" "curl" "git" "openssh"
                    # Kurtarma ve Editörler
                    "vim" "nano" "neovim" "bluez" "bluez-utils"
                    # Terminaller (GUI erişimi için şart)
                    "kitty" "alacritty" "terminator" "gnome-terminal" "konsole" "xfce4-terminal"
                    # Kabuklar
                    "bash" "zsh" "fish"
                )

                # 3. CONFIG TEMİZLİĞİ
                echo -e "${BLUE}[*] Cleaning configuration files...${NC}"
                for pkg in "${ALL_TARGETS[@]}"; do
                    target_config=""
                    case "$pkg" in
                        "hyprland"|"hyprlock") target_config="hypr" ;;
                        "waybar") target_config="waybar" ;;
                        "kitty") target_config="kitty" ;;
                        "alacritty") target_config="alacritty" ;;
                        "neovim") target_config="nvim" ;;
                        "vim") target_config="vim" ;;
                        "code") target_config="Code" ;;
                        "google-chrome") target_config="google-chrome" ;;
                        "discord") target_config="discord" ;;
                        "wofi") target_config="wofi" ;;
                        "dunst") target_config="dunst" ;;
                        "mako") target_config="mako" ;;
                        "ranger") target_config="ranger" ;;
                        "terminator") target_config="terminator" ;;
                        "rofi") target_config="rofi" ;;
                        "cava") target_config="cava" ;;
                        "fastfetch") target_config="fastfetch" ;;
                        "btop") target_config="btop" ;;
                        *) target_config="$pkg" ;;
                    esac
                    
                    CONFIG_PATH="$HOME/.config/$target_config"
                    if [ -d "$CONFIG_PATH" ]; then
                        cp -r "$CONFIG_PATH" "$BACKUP_DIR/"
                        rm -rf "$CONFIG_PATH"
                        echo -e "${RED}[-] Config Removed: ${NC} .config/$target_config (Package: $pkg)"
                    elif [ -d "$HOME/.$target_config" ]; then
                        cp -r "$HOME/.$target_config" "$BACKUP_DIR/"
                        rm -rf "$HOME/.$target_config"
                    fi
                done

                # 4. PAKET KALDIRMA (ARTIK GÜVENLİ)
                echo -e "\n${RED}╔══════════════════════════════════════════════════════╗${NC}"
                echo -e "${RED}║            UNINSTALLATION PHASE (SAFE MODE)          ║${NC}"
                echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
                echo -e "${YELLOW}Do you want to completely REMOVE the installed programs?${NC}"

                if ask_step "Uninstall packages from system (Safely)"; then
                    echo -e "\n${BLUE}[*] Uninstalling non-critical packages...${NC}"
                    for pkg in "${ALL_TARGETS[@]}"; do
                        
                        # KORUMA KONTROLÜ (Bu paket korumalı mı?)
                        if [[ " ${PROTECTED_PKGS[*]} " =~ " ${pkg} " ]]; then
                            echo -e "${YELLOW}[SKIP] Protected System Package: $pkg${NC}"
                            continue
                        fi

                        # Kaldırma İşlemi
                        if pacman -Qi "$pkg" &>/dev/null || dpkg -s "$pkg" &>/dev/null; then
                            echo -ne "   - Removing $pkg... "
                            if [ "$IS_ARCH" = true ]; then
                                # -Rs: Sadece paketi ve kullanılmayan bağımlılıklarını siler.
                                # -Rns YERİNE -Rs kullanıyoruz ki zincirleme silme yapmasın.
                                sudo pacman -Rs "$pkg" --noconfirm &>/dev/null
                            else
                                sudo apt-get remove --purge -y "$pkg" &>/dev/null
                            fi
                            echo -e "${GREEN}DONE${NC}"
                        fi
                    done
                    
                    # Yetim Paket Temizliği
                    echo -e "${BLUE}[*] Cleaning orphans (Safe)...${NC}"
                    if [ "$IS_ARCH" = true ]; then
                        sudo pacman -Rns $(pacman -Qtdq) --noconfirm 2>/dev/null
                    else
                        sudo apt-get autoremove -y 2>/dev/null
                    fi
                else
                    echo -e "${YELLOW}[SKIP] Packages kept installed. Only configs were reset.${NC}"
                fi

                # 5. GNOME & SHELL RESET
                if ask_step "Also reset GNOME and Shell settings to default"; then
                    [ -f /bin/bash ] && sudo chsh -s /bin/bash $USER 2>/dev/null
                    command -v dconf &>/dev/null && dconf reset -f /
                    rm -rf ~/.oh-my-zsh ~/.zshrc ~/.config/starship.toml
                    echo -e "${GREEN}[✓] Shell & GNOME reset.${NC}"
                fi

                echo -e "\n${GREEN}[✓] SMART CLEANUP COMPLETE.${NC}"
                echo -e "${YELLOW}[INFO] Config backups: $BACKUP_DIR${NC}"
                exit 0
            else
                echo -e "${GREEN}[*] Cancelled.${NC}"
                exit 0
            fi
        else
             exit 0
        fi
        ;;
    3)
        echo -e "Goodbye!"
        exit 0
        ;;
    *)
        echo -e "Invalid choice."
        exit 1
        ;;
esac

# --- RESUME SYSTEM SETUP ---
RESUME_LOG="$HOME/.arcon_progress.log"
RESUME_ENABLED=false

if [ -f "$RESUME_LOG" ]; then
    echo -e "${YELLOW}╔════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║      🔄 PREVIOUS INSTALLATION DETECTED      ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════╝${NC}"
    installed_count=$(wc -l < "$RESUME_LOG")
    echo -e "${BLUE}[INFO] Found $installed_count packages already installed${NC}"
    
    if ask_step "Resume from last checkpoint"; then
        RESUME_ENABLED=true
        echo -e "${GREEN}[✓] Resume mode enabled${NC}\n"
    else
        echo -e "${YELLOW}[*] Starting fresh installation...${NC}"
        rm -f "$RESUME_LOG"
    fi
fi

# ==============================================================================
# SECTOR 1: BASE SYSTEM & MIRRORS
# ==============================================================================

if ask_step "Update Base System (Mirrors/Keyrings)"; then
    base_done=true
    
    # ARCH LINUX İÇİN KESİN ÇÖZÜM
    if [ "$IS_ARCH" = true ]; then
        echo -e "${BLUE}[*] Fixing GPG keys and updating system...${NC}"
        
        # 1. GPG & BlackArch Emergency Fix
        echo -e "${YELLOW}[*] Cleaning GPG environment and handling repo conflicts...${NC}"
        
        # BlackArch takılmasını önlemek için geçici olarak devre dışı bırak
        if grep -q "^\[blackarch\]" /etc/pacman.conf; then
            echo -e "${YELLOW}[*] Temporarily disabling BlackArch to fix keyrings...${NC}"
            sudo sed -i 's/^\[blackarch\]/#\[blackarch\]/' /etc/pacman.conf
            sudo sed -i 's/^Include = \/etc\/pacman.d\/blackarch-mirrorlist/#Include = \/etc\/pacman.d\/blackarch-mirrorlist/' /etc/pacman.conf
        fi

        # Tüm GPG süreçlerini sonlandır
        gpgconf --kill all 2>/dev/null
        sudo gpgconf --homedir /etc/pacman.d/gnupg --kill all 2>/dev/null
        sudo killall gpg-agent 2>/dev/null || true
        
        # Bozuk anahtar ve senkronizasyon dosyalarını temizle
        sudo rm -rf /etc/pacman.d/gnupg 2>/dev/null
        sudo rm -rf /var/lib/pacman/sync/* 2>/dev/null
        
        # 2. Key Initialization (Temiz Sayfa)
        echo -e "${YELLOW}[*] Initializing pacman keys...${NC}"
        sudo pacman-key --init
        sudo pacman-key --populate archlinux
        
        # 3. Keyring Update
        echo -e "${BLUE}[*] Updating Arch Keyring...${NC}"
        # Sadece resmi depolarla güncelleme yap
        sudo pacman -Sy archlinux-keyring --noconfirm || { 
            echo -e "${RED}[ERROR] Keyring update failed! Check your internet.${NC}"; 
            exit 1; 
        }
        
        # 4. BlackArch Recovery (Eğer varsa geri aç ve imzala)
        if grep -q "^#\[blackarch\]" /etc/pacman.conf; then
            echo -e "${BLUE}[*] Re-enabling and signing BlackArch keys...${NC}"
            sudo sed -i 's/^#\[blackarch\]/\[blackarch\]/' /etc/pacman.conf
            sudo sed -i 's/^#Include = \/etc\/pacman.d\/blackarch-mirrorlist/Include = \/etc\/pacman.d\/blackarch-mirrorlist/' /etc/pacman.conf
            # BlackArch anahtarını (noptrix) güvenilir olarak imzala
            sudo pacman-key --lsign-key 4345771566D76030457303332944B067D796237B 2>/dev/null || true
        fi
        
        # 5. Critical Deps (bc, git, base-devel, reflector)
        echo -e "${BLUE}[*] Installing dependencies...${NC}"
        sudo pacman -S --needed --noconfirm bc git base-devel reflector || { 
            echo -e "${RED}[ERROR] Prerequisite install failed!${NC}"; 
            exit 1; 
        }
        
        # 6. System Upgrade
        sudo pacman -Su --noconfirm
        
        # 7. Reflector (Canlı Akış, Düzeltilmiş Tablo ve Vurgulama)
        if command -v reflector &> /dev/null; then
            echo -e "${BLUE}[*] Benchmarking top 20 HTTPS mirrors... (Live Output)${NC}"
            echo -e "${YELLOW}[INFO] Colors: ${GREEN}>0 (Fast)${NC} | ${RED}0 (Timeout)${NC}"
            echo -e "${BLUE}-----------------------------------------------------${NC}"

            # TEK KOMUT ZİNCİRİ
            sudo reflector \
                --verbose \
                --protocol https \
                --latest 20 \
                --sort rate \
                --download-timeout 5 \
                --save /etc/pacman.d/mirrorlist 2>&1 | \
                awk '
                BEGIN { count=1 } 
                {
                    # 1. ADIM: BAŞLIKLARI AYIKLA (Numara Verme)
                    # "rating" veya "Server...Rate" içeren satırları olduğu gibi bas
                    if ($0 ~ /rating/ || $0 ~ /Server.*Rate.*Time/) {
                        print $0
                        next # Sonraki satıra geç, sayacı artırma
                    }

                    # 2. ADIM: RENKLENDİRME (Hız ve Zaman)
                    for (i=1; i<=NF; i++) {
                        # Hız Birimi Kontrolü
                        if ($i ~ /^[KM]i?B\/s$/) {
                            val = $(i-1)
                            if (val == 0 || val == "0.00") color = "\033[1;31m" # KIRMIZI
                            else color = "\033[1;32m" # YEŞİL
                            $(i-1) = color $(i-1)
                            $i = $i "\033[0m"
                        }
                        # Zaman Birimi Kontrolü
                        else if ($i ~ /^s$|^second\(s\)\.?$/) {
                            val = $(i-1)
                            if (val == 0 || val == "0.00") color = "\033[1;31m" # KIRMIZI
                            else color = "\033[1;32m" # YEŞİL
                            $(i-1) = color $(i-1)
                            $i = $i "\033[0m"
                        }
                    }
                    
                    # 3. ADIM: NUMARALANDIRMA (Sadece sunuculara)
                    printf "%2d) %s\n", count++, $0;
                    fflush();
                }'
            
            # --- SONUÇ ÖZETİ (1. SIRA VURGULU) ---
            echo -e "${BLUE}-----------------------------------------------------${NC}"
            echo -e "${GREEN}[OK] Mirrorlist updated successfully.${NC}"
            echo -e "${YELLOW}[INFO] Final Selection (Top 10 Fastest):${NC}"
            echo -e "${BLUE}-----------------------------------------------------${NC}"
            
            # "awk" içine dışarıdan renk değişkenlerini (-v) ile alıyoruz
            grep "^Server" /etc/pacman.d/mirrorlist | head -n 10 | awk -v green="${GREEN}" -v nc="${NC}" '
            {
                # $3 sütunu URL adresidir
                url = $3
                
                if (NR == 1) {
                    # İLK SATIR: Yeşil renk, numara 1 ve ok işareti
                    printf "%s 1. %s  <-- ACTIVE MIRROR%s\n", green, url, nc
                } else {
                    # DİĞER SATIRLAR: Standart beyaz
                    printf " %2d. %s\n", NR, url
                }
            }'
            
            echo -e "${BLUE}-----------------------------------------------------${NC}"

            # --- HIZ ÖLÇÜMÜ (CLOUDFLARE TEST) ---
            echo -e "${BLUE}[*] Measuring real download speed (Cloudflare Test)...${NC}"
            
            speed_bps=$(curl -s -o /dev/null -w "%{speed_download}" --connect-timeout 5 --max-time 6 "https://speed.cloudflare.com/__down?bytes=10000000")
            
            if [ -z "$speed_bps" ] || [ "$speed_bps" = "0.000" ]; then speed_kb=0; else
                speed_kb=$(echo "$speed_bps" | awk '{printf "%d", $1/1024}')
            fi
            
            echo -e "${BOLD}>> Current Download Speed: ${speed_kb} KB/s${NC}"
            
            if [ "$speed_kb" -lt 500 ]; then
                echo -e "${RED}[!] WARNING: Connection seems slow (<500 KB/s).${NC}"
            else
                echo -e "${GREEN}[OK] Connection speed is good.${NC}"
            fi
            echo -e "${BLUE}-----------------------------------------------------${NC}"

        else
            echo -e "${YELLOW}[WARN] Reflector not found, skipping mirror optimization.${NC}"
        fi

    # DEBIAN/UBUNTU İÇİN
    else
        echo -e "${BLUE}[*] Updating Debian/Ubuntu lists...${NC}"
        sudo apt-get update
        sudo apt-get install -y bc git build-essential
        sudo apt-get upgrade -y
    fi
    # YAY KURULUMU (Daha Kararlı Yöntem: yay-bin)
    if [ "$IS_ARCH" = true ] && ! command -v yay &> /dev/null; then
        echo -e "${BLUE}[*] Installing YAY (AUR Helper)...${NC}"
        rm -rf yay-bin 2>/dev/null
        git clone https://aur.archlinux.org/yay-bin.git || { echo -e "${RED}[ERROR] YAY clone failed!${NC}"; exit 1; }
        cd yay-bin && makepkg -si --noconfirm || { echo -e "${RED}[ERROR] YAY build failed!${NC}"; exit 1; }
        cd .. && rm -rf yay-bin
        echo -e "${GREEN}[OK] YAY installed successfully.${NC}"
    fi
fi
# ==============================================================================
# SECTOR 2: GNOME, GAMING & GPU STACK (CHAINED SETUP)
# ==============================================================================
gnome_done=false

# ==========================================
# ADIM A: GNOME KURULUM VE AYARLARI
# ==========================================
# DÜZELTME: Her şeyi (İndirme + Ayar) tek bir soru bloğuna aldık.
if ask_step "Apply GNOME Settings (Theme + Config)"; then

    # ------------------------------------------------------------------------------
    # 1. Bağımlılıkları (Tema ve Pano Araçları) İndir
    # ------------------------------------------------------------------------------
    echo -e "${BLUE}[*] Installing GNOME dependencies...${NC}"

    if [ "$IS_ARCH" = true ]; then
        # Arch Linux: Resmi depolardan wl-clipboard
        sudo pacman -S --noconfirm --needed wl-clipboard 
        
        # AUR Paketleri: Tema ve eklentiler (yay kontrolü ile)
        if command -v yay &> /dev/null; then
            yay -S --noconfirm --needed gnome-shell-extension-clipboard-indicator adw-gtk-theme-git
        else
            echo -e "${RED}[!] 'yay' bulunamadı. Tema paketleri atlanıyor.${NC}"
        fi
    else
        # Debian/Ubuntu
        sudo apt-get install -y adw-gtk-theme wl-clipboard 2>/dev/null
    fi

    # ------------------------------------------------------------------------------
    # 2. Config Dosyasını İşle (gno.conf)
    # ------------------------------------------------------------------------------
    if [ -f "configs/gno.conf" ]; then
        echo -e "${BLUE}[*] Configuring GNOME environment...${NC}"
        
        # Eski Klasörleri Sıfırla
        dconf reset -f /org/gnome/desktop/app-folders/
        
        # Kullanıcı Adını Yerleştir ve Yükle
        echo -e "${BLUE}[*] Loading configuration from gno.conf...${NC}"
        sed "s|USER_PLACEHOLDER|$USER|g" configs/gno.conf > /tmp/gno_final.conf
        
        if dconf load / < /tmp/gno_final.conf; then
            rm /tmp/gno_final.conf
            gnome_done=true
            echo -e "${GREEN}[OK] GNOME settings applied successfully.${NC}"
        else
            echo -e "${RED}[ERROR] Failed to load gno.conf! Check syntax.${NC}"
            rm /tmp/gno_final.conf
        fi
    else
        echo -e "${RED}[ERROR] configs/gno.conf not found!${NC}"
    fi
    
    # 3. Debloat (İsteğe Bağlı ve Güvenli Mod)
    if ask_step "Remove GNOME Bloatware"; then
        bloat_packages=("gnome-tour" "gnome-weather" "gnome-maps" "gnome-contacts" "gnome-music" "epiphany")
        
        echo -e "${BLUE}[*] Removing bloatware...${NC}"
        
        if [ "$IS_ARCH" = true ]; then
            # Hata vermeden sadece yüklü olanları sil
            for pkg in "${bloat_packages[@]}"; do
                if pacman -Qs "$pkg" > /dev/null; then
                    sudo pacman -Rns "$pkg" --noconfirm 2>/dev/null
                    echo "Removed: $pkg"
                fi
            done
        else
            sudo apt-get remove -y ${bloat_packages[*]} 2>/dev/null
        fi
        echo -e "${GREEN}[OK] System cleaned.${NC}"
    fi
fi

# ==========================================
# ADIM B: GAMING & GPU (GNOME'A BAĞLI)
# ==========================================
if [ "$gnome_done" = true ]; then
    
    if [ "$IS_ARCH" = true ] && ask_step "Enable Gaming Mode (Steam, GPU Drivers)"; then
        
        # 1. Multilib Kontrolü
        if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
            echo -e "${YELLOW}[*] Enabling Multilib repository...${NC}"
            sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
            sudo pacman -Sy > /dev/null
        fi

        # 2. Kurulacak Paketlerin Listesini Hazırla
        final_install_list=()
        base_gaming="steam gamemode lib32-gamemode"
        
        echo -e "\n${YELLOW}Select your GPU for optimized drivers:${NC}"
        gpu_pkgs=""
        select gpu in "Nvidia" "AMD" "Intel" "Skip"; do
            case $gpu in
                Nvidia) gpu_pkgs="nvidia-utils lib32-nvidia-utils nvidia-settings"; break ;;
                AMD)    gpu_pkgs="mesa lib32-mesa xf86-video-amdgpu vulkan-radeon"; break ;;
                Intel)  gpu_pkgs="mesa lib32-mesa vulkan-intel"; break ;;
                Skip)   break ;;
            esac
        done

        # 3. Smart Check
        echo -e "${BLUE}[*] Checking missing packages...${NC}"
        all_pkgs="$base_gaming $gpu_pkgs"
        
        for pkg in $all_pkgs; do
            if ! pacman -Qi "$pkg" &>/dev/null; then
                final_install_list+=("$pkg")
            else
                echo -e "${BLUE}[SKIP] $pkg is already installed.${NC}"
            fi
        done

        # 4. Kurulum (Görsel Bar ile)
        count=${#final_install_list[@]}
        
        if [ "$count" -gt 0 ]; then
            # Bar Fonksiyonu
            update_ui() {
                percent=$(($1 * 100 / $2)); filled=$((percent * 40 / 100)); empty=$((40 - filled))
                bar=$(printf "%0.s█" $(seq 1 $filled))$(printf "%0.s░" $(seq 1 $empty))
                echo -ne "\033[2A\r"
                echo -ne "${BOLD}[${GREEN}${bar}${NC}${BOLD}] ${percent}%${NC} \033[K\nProcessing: ${CYAN}$3${NC}\033[K\n"
            }

            echo -e "\n\n"
            tput civis
            idx=0
            update_ui 0 $count "Initializing..."
            
            for pkg in "${final_install_list[@]}"; do
                ((idx++))
                update_ui $idx $count "$pkg"
                sudo pacman -S --noconfirm --needed "$pkg" &> /dev/null
            done
            
            update_ui $count $count "DONE"
            tput cnorm
            
            # GameMode Config
            mkdir -p ~/.config/gamemode
            echo -e "[general]\ndesiredgov=performance\nigpu_desiredgov=performance" > ~/.config/gamemode/gamemode.ini
            sudo usermod -aG gamemode $USER
            
            echo -e "${GREEN}[✓] Gaming Environment Ready!${NC}"
            if [[ "$gpu" == "Nvidia" ]]; then
                echo -e "${YELLOW}[NOTE] Add 'nvidia_drm.modeset=1' to your kernel parameters!${NC}"
            fi
        else
            echo -e "${GREEN}[OK] All Gaming/GPU packages are already installed.${NC}"
        fi
    fi
else
    echo -e "${YELLOW}[SKIP] Gaming Setup skipped (Requires GNOME settings).${NC}"
fi

# ==============================================================================
# SECTOR 3: PACKAGE INSTALLATION (HYBRID MODULE: PRESETS + PACS.TXT)
# ==============================================================================

if ask_step "Start Package Installation Module"; then
    
    # --- A) KUYRUĞU OLUŞTURMA ---
    FINAL_QUEUE=()
    
    # 1. ESSENTIALS (OTOMATİK EKLEME)
    echo -e "\n${CYAN}--- Default: Essential Packages ---${NC}"
    echo -e "${YELLOW}Packages included:${NC} ${DIM}${PKG_ESSENTIALS[*]}${NC}"
    
    FINAL_QUEUE=("${PKG_ESSENTIALS[@]}")
    echo -e "${GREEN}[+] Added to queue automatically.${NC}"

    # 2. MEDIA & OFFICE
    echo -e "\n${CYAN}--- Option: Media & Office Suite ---${NC}"
    echo -e "${YELLOW}Packages included:${NC} ${DIM}${PKG_MEDIA[*]}${NC}" 
    
    if ask_step "Include these packages"; then
        FINAL_QUEUE+=("${PKG_MEDIA[@]}")
        echo -e "${GREEN}[+] Media & Office packages added.${NC}"
    else
        echo -e "${RED}[-] Skipped Media & Office.${NC}"
    fi

    # 3. CYBER SECURITY
    echo -e "\n${CYAN}--- Option: Cyber Security Tools ---${NC}"
    echo -e "${YELLOW}Packages included:${NC} ${DIM}${PKG_CYBER[*]}${NC}"
    
    if ask_step "Include these packages"; then
        FINAL_QUEUE+=("${PKG_CYBER[@]}")
        echo -e "${GREEN}[+] Cyber Security packages added.${NC}"
    else
        echo -e "${RED}[-] Skipped Cyber Security.${NC}"
    fi

    # 4. REMOTE SUPPORT
    echo -e "\n${CYAN}--- Option: Remote Support Tools ---${NC}"
    echo -e "${YELLOW}Packages included:${NC} ${DIM}${PKG_REMOTE[*]}${NC}"
    
    if ask_step "Include Remote Desktop Tools (AnyDesk,RustDesk)"; then
        FINAL_QUEUE+=("${PKG_REMOTE[@]}")
        echo -e "${GREEN}[+] Remote Support packages added.${NC}"
        
        echo -e "${YELLOW}[INFO] Note: TeamViewer/AnyDesk often require enabling their services later:${NC}"
        echo -e "${DIM}        sudo systemctl enable --now teamviewerd${NC}"
        echo -e "${DIM}        sudo systemctl enable --now anydesk${NC}"
    else
        echo -e "${RED}[-] Skipped Remote Support.${NC}"
    fi

    # 5. POWER TOOLS
    echo -e "\n${CYAN}--- Option: Power Tools & Privacy ---${NC}"
    echo -e "${YELLOW}Packages included:${NC} ${DIM}${PKG_POWER[*]}${NC}"
    
    if ask_step "Include Power User Tools (Virtualization, Privacy, Optimization)"; then
        FINAL_QUEUE+=("${PKG_POWER[@]}")
        echo -e "${GREEN}[+] Power Tools added.${NC}"
        
        echo -e "${YELLOW}[INFO] For Virtual Machines to work, enable libvirtd later:${NC}"
        echo -e "${DIM}        sudo systemctl enable --now libvirtd${NC}"
        echo -e "${YELLOW}[INFO] For Ananicy (Auto-Nice) optimization:${NC}"
        echo -e "${DIM}        sudo systemctl enable --now ananicy-cpp${NC}"
    else
        echo -e "${RED}[-] Skipped Power Tools.${NC}"
    fi

    # 6. PACS.TXT KONTROLÜ (DÜZELTİLDİ: ARTIK SORUYOR)
    if [ -f "pacs.txt" ]; then
        echo -e "\n${CYAN}--- Option: Custom Packages (pacs.txt) ---${NC}"
        echo -e "${YELLOW}Found 'pacs.txt' file with custom packages.${NC}"
        
        if ask_step "Include custom packages from 'pacs.txt'"; then
            echo -e "${BLUE}[*] Reading 'pacs.txt'...${NC}"
            found_custom=false
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Yorumları sil (# sonrası) ve baştaki/sondaki boşlukları temizle
                clean_line=$(echo "$line" | sed 's/#.*//' | xargs)
                
                if [ -n "$clean_line" ]; then
                    FINAL_QUEUE+=("$clean_line")
                    found_custom=true
                fi
            done < pacs.txt
            
            if [ "$found_custom" = true ]; then
                echo -e "${GREEN}[+] Custom packages from pacs.txt added.${NC}"
            else
                echo -e "${YELLOW}[!] pacs.txt is empty or contains only comments.${NC}"
            fi
        else
            echo -e "${RED}[-] Skipped pacs.txt.${NC}"
        fi
    else
        # pacs.txt yoksa sessizce geç
        : 
    fi

    # ==============================================================================
    # DUPLICATE REMOVER (TEKRARLAYAN PAKETLERİ TEMİZLE)
    # ==============================================================================
    # Listeyi alfabetik sıraya dizer ve kopyaları (örn: 2 tane git) siler.
    if [ ${#FINAL_QUEUE[@]} -gt 0 ]; then
        echo -e "\n${BLUE}[*] Optimizing queue (Removing duplicates & Sorting)...${NC}"
        FINAL_QUEUE=($(printf "%s\n" "${FINAL_QUEUE[@]}" | sort -u))
    fi

    # --- B) AKILLI ANALİZ VE TABLO ---
    
    if [ ${#FINAL_QUEUE[@]} -eq 0 ]; then
        echo -e "\n${YELLOW}[!] No packages selected. Skipping to next module...${NC}"
        skip_pacs=true
    else
        skip_pacs=false
    fi

    if [ "$skip_pacs" = false ]; then
        echo -e "\n${BLUE}[*] Processing package list...${NC}"
        
        total_bytes=0
        pkg_list_output=""
        install_list=()
        aur_list=()

        # Sadece Arch Linux için detaylı boyut analizi
        if [ "$IS_ARCH" = true ]; then
            echo -e "${BLUE}[*] Calculating download sizes (Pacman)...${NC}"
            pkg_list_output+="${BOLD}PACKAGE NAME|STATUS / SIZE${NC}\n"
            pkg_list_output+="------------|-------------\n"

            for pkg in "${FINAL_QUEUE[@]}"; do
                if pacman -Qi "$pkg" &>/dev/null; then
                    pkg_list_output+="${BLUE}$pkg|INSTALLED${NC}\n"
                    continue
                fi

                size_info=$(pacman -Si "$pkg" 2>/dev/null | grep "Download Size")
                
                if [ -n "$size_info" ]; then
                    install_list+=("$pkg") 
                    
                    size=$(echo "$size_info" | awk '{print $4}')
                    unit=$(echo "$size_info" | awk '{print $5}')
                    
                    if [[ "$unit" == "MiB" ]] && (( $(echo "$size > 100" | bc -l 2>/dev/null || echo 0) )); then
                        size_display="${RED}$size $unit${NC}"
                    else
                        size_display="${GREEN}$size $unit${NC}"
                    fi
                    
                    # Basit boyut toplama (Hata verirse yoksay)
                    if [[ "$unit" == "MiB" ]]; then
                        total_bytes=$(echo "$total_bytes + ($size * 1024)" | bc 2>/dev/null || echo "$total_bytes")
                    elif [[ -n "$size" ]]; then 
                        total_bytes=$(echo "$total_bytes + $size" | bc 2>/dev/null || echo "$total_bytes")
                    fi
                    pkg_color="${GREEN}"
                else
                    aur_list+=("$pkg") 
                    pkg_color="${RED}"
                    size_display="${YELLOW}(AUR Build)${NC}"
                fi
                pkg_list_output+="${pkg_color}$pkg${NC}|$size_display\n"
            done
            
            echo -e "\n${BLUE}========== INSTALLATION PREVIEW ==========${NC}"
            echo -e "$pkg_list_output" | column -t -s "|"
            echo -e "${BLUE}==========================================${NC}"

            total_mb=$(echo "scale=2; $total_bytes / 1024" | bc 2>/dev/null || echo "0")
            echo -e "${BOLD}>> Total Download Required: ~${total_mb} MB${NC}"
            echo -e "${BOLD}>> Queued: ${#install_list[@]} Official, ${#aur_list[@]} AUR packages${NC}"

        else
            # Debian/Ubuntu için basit liste
            install_list=("${FINAL_QUEUE[@]}")
            echo -e "${BOLD}>> Queued Packages: ${#install_list[@]}${NC}"
        fi
        
        if ! ask_step "Proceed with installation"; then 
            skip_pacs=true
            echo -e "${YELLOW}[!] Package installation cancelled by user.${NC}"
        fi
    fi

    # --- C) KURULUM İŞLEMİ ---
    
    if [ "$skip_pacs" = false ]; then
        
        total_count=$((${#install_list[@]} + ${#aur_list[@]}))
        declare -a setup_history=()
        
        if [ "$total_count" -eq 0 ]; then
            echo -e "\n${GREEN}[✓] All selected packages are already installed.${NC}"
        else
            tput cnorm
            current_idx=0
            
            # --- UI FONKSİYONU ---
            print_status_bar() {
                local current=$1
                local total=$2
                local pkg_name=$3
                local width=40 
                local percent=$((current * 100 / total))
                
                local filled=$((percent * width / 100))
                local empty=$((width - filled))
                local bar_fill=""; local bar_empty=""
                [ "$filled" -gt 0 ] && bar_fill=$(printf "%0.s█" $(seq 1 $filled))
                [ "$empty" -gt 0 ]  && bar_empty=$(printf "%0.s░" $(seq 1 $empty))
                
                clear
                
                # GEÇMİŞ
                echo -e "${DIM}--- Recent Activity ---${NC}"
                local history_len=${#setup_history[@]}
                local start_idx=$((history_len > 5 ? history_len - 5 : 0))
                for ((i=start_idx; i<history_len; i++)); do
                    echo -e "${setup_history[$i]}"
                done
                if [ "$history_len" -lt 5 ]; then
                    for ((k=0; k<(5-history_len); k++)); do echo ""; done
                fi
                echo -e "${DIM}-----------------------${NC}\n"

                # BAR
                echo -e "${BLUE}=========================================${NC}"
                echo -e "${GREEN}      ArCoN Installation Progress        ${NC}"
                echo -e "${BLUE}=========================================${NC}"
                echo -e "${BOLD}[${GREEN}${bar_fill}${GRAY}${bar_empty}${NC}${BOLD}] ${percent}%${NC}"
                
                if [ "$percent" -eq 100 ]; then
                    echo -e "Status: ${GREEN}COMPLETE${NC}"
                    echo -e "${BLUE}=========================================${NC}"
                else
                    echo -e "Processing: ${CYAN}${pkg_name}${NC}"
                    if [ "$IS_ARCH" = true ]; then
                         echo -e "${YELLOW}>> Interaction might be required for AUR${NC}"
                    fi
                    echo -e "${DIM}-----------------------------------------${NC}"
                fi
            }

            # RESMİ PAKETLER
            for pkg in "${install_list[@]}"; do
                ((current_idx++))
                print_status_bar $current_idx $total_count "$pkg"
                
                if [ "$IS_ARCH" = true ]; then
                    sudo pacman -S --needed --noconfirm --color always "$pkg" &> /dev/null
                    check_cmd="pacman -Qi $pkg"
                else
                    sudo apt-get install -y "$pkg" &> /dev/null
                    check_cmd="dpkg -s $pkg"
                fi
                
                if $check_cmd &> /dev/null; then
                    setup_history+=("${GREEN}[✓] Installed: $pkg${NC}")
                else
                    setup_history+=("${RED}[X] Failed: $pkg${NC}")
                fi
                sleep 0.2
            done

            # AUR PAKETLER (Sadece Arch için)
            if [ "$IS_ARCH" = true ]; then
                for pkg in "${aur_list[@]}"; do
                    ((current_idx++))
                    print_status_bar $current_idx $total_count "$pkg (AUR)"
                    
                    if command -v yay &> /dev/null; then
                        if yay -S --needed --answerdiff=None --answerclean=None "$pkg"; then
                            if pacman -Qi "$pkg" &> /dev/null; then
                                setup_history+=("${GREEN}[✓] Installed (AUR): $pkg${NC}")
                            else
                                setup_history+=("${GREEN}[?] Attempted (AUR): $pkg${NC}")
                            fi
                        else
                            setup_history+=("${RED}[X] Failed (AUR): $pkg${NC}")
                        fi
                    else
                         setup_history+=("${RED}[X] Skip (AUR): yay not found${NC}")
                    fi
                    sleep 0.2
                done
            fi
            
            # TAMAMLANDI
            print_status_bar $total_count $total_count "Complete"
            echo -e "\n${GREEN}[✓] Package installation completed!${NC}"
        fi
    fi
else
    echo -e "${YELLOW}[!] Package installation module skipped by user.${NC}"
fi
# ==============================================================================
# SECTOR 4: BLACKARCH REPOSITORY MANAGER (SMART CHECK)
# ==============================================================================
if [ "$IS_ARCH" = true ]; then
    while true; do
        echo -e "\n${BLUE}=== BlackArch Repository Manager ===${NC}"
        # Smart Check Status Indicator
        if grep -q "^\[blackarch\]" /etc/pacman.conf; then
            echo -e "${GREEN}[Status: Repository is ACTIVE]${NC}"
        else
            echo -e "${RED}[Status: Repository is NOT ENABLED]${NC}"
        fi
        
        echo -e "1) Enable Repository & Prep System"
        echo -e "2) Install Tools (Categories or Full)"
        echo -e "3) Remove BlackArch & Cleanup"
        echo -e "4) Skip / Back to Main Menu"
        read -p "Select an option [1-4]: " ba_choice

        case $ba_choice in
            1)
                # --- SMART CHECK: REPO ---
                if grep -q "^\[blackarch\]" /etc/pacman.conf; then
                    echo -e "${BLUE}[SKIP] BlackArch repository is already active.${NC}"
                else
                    echo -e "${YELLOW}[*] Installing BlackArch repository...${NC}"
                    curl -fsSL https://blackarch.org/strap.sh -o strap.sh || { echo -e "${RED}Download failed!${NC}"; break; }
                    chmod +x strap.sh
                    sudo ./strap.sh
                    rm -f strap.sh
                    # Key Signing
                    sudo pacman-key --lsign-key 4345771566D76030457303332944B067D796237B
                fi

                # --- SMART CHECK: PROVIDER LOCK ---
                echo -e "${BLUE}[*] Checking for provider locks (Java, Rust, OpenCL)...${NC}"
                # Eğer zaten kuruluysa '--needed' sayesinde atlanacak
                sudo pacman -S --needed --noconfirm jdk17-openjdk jdk11-openjdk rust opencl-mesa

                # --- SMART CHECK: MULTILIB ---
                if grep -q "^\[multilib\]" /etc/pacman.conf && ! grep -q "^#\[multilib\]" /etc/pacman.conf; then
                    echo -e "${BLUE}[SKIP] Multilib is already enabled.${NC}"
                else
                    echo -e "${YELLOW}[*] Enabling multilib repository...${NC}"
                    sudo sed -i '/^\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
                    sudo pacman -Sy
                fi
                echo -e "${GREEN}[OK] Preparation complete.${NC}"
                ;;

            2)
                # --- SMART CHECK: INSTALLATION ---
                if ! grep -q "^\[blackarch\]" /etc/pacman.conf; then
                    echo -e "${RED}[ERROR] Repository not found! Please run Option 1 first.${NC}"
                else
                    echo -e "\n${YELLOW}Installation Menu (Manual/Interactive Mode):${NC}"
                    echo -e "1) Full BlackArch (All Tools - 20GB+)"
                    echo -e "2) Core Pentest Groups (WebApp, Net, Wireless)"
                    echo -e "3) Back"
                    read -p "Selection: " inst_choice
                    
                    case $inst_choice in
                        1|2)
                            echo -e "\n${BLUE}========== SELECTION GUIDE ==========${NC}"
                            echo -e "${BOLD}How to pick/cancel packages:${NC}"
                            echo -e " - Press ${GREEN}[Enter]${NC} for ALL (Default)"
                            echo -e " - Type ${CYAN}1 5 10${NC} for specific tools"
                            echo -e " - Type ${RED}^10 ^15${NC} to ${RED}EXCLUDE${NC} packages 10 and 15"
                            echo -e " - Range: ${CYAN}1-50${NC} (Installs first 50 tools)"
                            echo -e "${BLUE}=====================================${NC}"
                            
                            read -p "Ready? Press [Enter] to launch pacman..."
                            
                            if [ "$inst_choice" == "1" ]; then
                                sudo pacman -S blackarch --needed --overwrite '*'
                            else
                                sudo pacman -S blackarch-webapp blackarch-networking blackarch-wireless --needed --overwrite '*'
                            fi
                            
                            [ $? -eq 0 ] && echo -e "${GREEN}[✓] Success.${NC}" || echo -e "${RED}[!] Failed.${NC}"
                            ;;
                        *) continue ;;
                    esac
                fi
                ;;
            3)
                # --- SMART CHECK: REMOVAL ---
                if ! grep -q "^\[blackarch\]" /etc/pacman.conf; then
                    echo -e "${BLUE}[SKIP] BlackArch is not present in your system.${NC}"
                else
                    echo -e "${RED}[*] Removing BlackArch repository and cleaning keys...${NC}"
                    sudo sed -i '/\[blackarch\]/,+1d' /etc/pacman.conf
                    sudo pacman-key --delete 4345771566D76030457303332944B067D796237B 2>/dev/null
                    sudo pacman -Syy
                    echo -e "${GREEN}[OK] BlackArch removed successfully.${NC}"
                fi
                ;;

            4)
                echo -e "${BLUE}[*] Returning to Main Menu...${NC}"
                break
                ;;

            *)
                echo -e "${RED}Invalid selection!${NC}"
                ;;
        esac
    done
fi

# ==============================================================================
# SECTOR 6: HYPRLAND & DESKTOP (SMART CHECK)
# ==============================================================================

if [ "$IS_ARCH" = true ] && ask_step "Install Hyprland Environment"; then
    echo -e "${BLUE}[*] Checking Hyprland ecosystem...${NC}"
    
    # 1. Temel Sistem Akıllı Kontrolü
    # Kurulacak paket listesi
    hypr_pkgs="hyprland hyprlock hypridle xdg-desktop-portal-hyprland kitty wofi waybar dolphin"
    install_list=""

    for pkg in $hypr_pkgs; do
        if pacman -Qi "$pkg" &>/dev/null; then
            echo -e "${BLUE}[SKIP] $pkg is already installed.${NC}"
        else
            echo -e "${GREEN}[+] Queued for install: $pkg${NC}"
            install_list="$install_list $pkg"
        fi
    done

    # 2. Eksik Paketlerin Kurulumu
    if [ -n "$install_list" ]; then
        echo -e "${BLUE}[*] Installing missing Hyprland packages...${NC}"
        # $AUR_MGR (yay) kullanarak kuruyoruz
        $AUR_MGR $install_list || { echo -e "${RED}[ERROR] Hyprland install failed!${NC}"; exit 1; }
    else
        echo -e "${GREEN}[OK] Hyprland base system is already fully installed.${NC}"
    fi
    
    # 3. Konfigürasyon Yedekleme (Sadece klasör doluysa)
    if [ -d "$HOME/.config/hypr" ]; then
        if [ "$(ls -A $HOME/.config/hypr 2>/dev/null)" ]; then
            echo -e "${YELLOW}[*] Backing up existing Hyprland config to ~/.config/hypr.bak_$(date +%s)...${NC}"
            mv "$HOME/.config/hypr" "$HOME/.config/hypr.bak_$(date +%s)"
        fi
    fi

    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${GREEN}      SELECT A HYPRLAND THEME (DOTFILES)  ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${YELLOW}Which configuration style do you want to install?${NC}"
    
    options=("Ax-Shell (Minimal & Clean)" "Hyprdots (Feature Rich)" "ML4W (Beginner Friendly)" "JaKooLit (Gaming Optimized)" "Skip Theme")
    
    select opt in "${options[@]}"; do
        case $opt in
            "Ax-Shell (Minimal & Clean)")
                echo -e "${BLUE}[*] Preparing Ax-Shell...${NC}"
                rm -f install_ax.sh 2>/dev/null
                curl -s https://raw.githubusercontent.com/Axenide/Ax-Shell/main/install.sh -o install_ax.sh
                
                # Debloat Fırsatı
                if ask_step "Do you want to edit/debloat the installer script before running"; then
                    nano install_ax.sh
                fi
                
                chmod +x install_ax.sh
                ./install_ax.sh
                rm install_ax.sh
                break
                ;;
                
            "Hyprdots (Feature Rich)")
                echo -e "${BLUE}[*] Preparing Hyprdots (Prasanth Rangan)...${NC}"
                echo -e "${YELLOW}[INFO] This is a heavy config. It installs many extras.${NC}"
                
                # Temp klasör temizliği (Varsa sil)
                rm -rf ~/hyprdots-temp 2>/dev/null
                
                git clone --depth 1 https://github.com/prasanthrangan/hyprdots.git ~/hyprdots-temp
                cd ~/hyprdots-temp/Scripts
                
                if ask_step "Edit installation script (install.sh) to remove bloat"; then
                    nano install.sh
                fi
                
                ./install.sh
                cd ~
                rm -rf ~/hyprdots-temp
                break
                ;;
                
            "ML4W (Beginner Friendly)")
                echo -e "${BLUE}[*] Preparing ML4W Dotfiles (Stephan Raabe)...${NC}"
                rm -rf ~/ml4w-dotfiles 2>/dev/null
                
                git clone --depth 1 https://github.com/mylinuxforwork/dotfiles.git ~/ml4w-dotfiles
                cd ~/ml4w-dotfiles
                
                if ask_step "Edit installer.sh before running"; then
                    nano installer.sh
                fi
                
                ./installer.sh
                cd ~
                break
                ;;

            "JaKooLit (Gaming Optimized)")
                echo -e "${BLUE}[*] Preparing JaKooLit Dotfiles...${NC}"
                rm -rf ~/JaKooLit-Dots 2>/dev/null
                
                git clone --depth 1 https://github.com/JaKooLit/Hyprland-Dots.git ~/JaKooLit-Dots
                cd ~/JaKooLit-Dots
                chmod +x install.sh
                
                if ask_step "Edit install.sh before running"; then
                    nano install.sh
                fi
                
                ./install.sh
                cd ~
                rm -rf ~/JaKooLit-Dots
                break
                ;;

            "Skip Theme")
                echo -e "${YELLOW}[*] Skipping theme installation. You have a vanilla Hyprland.${NC}"
                
                # ArCoN Varsayılanları
                echo -e "${BLUE}[*] Applying ArCoN default configs...${NC}"
                mkdir -p ~/.config/hypr 
                if [ -d "configs/hypr" ]; then
                    cp -r configs/hypr/* ~/.config/hypr/
                fi
                break
                ;;
                
            *) echo -e "${RED}Invalid option $REPLY${NC}";;
        esac
    done
fi

# ==============================================================================
# SECTOR 7: CONFIG RESTORATION (Terminator/Wallpapers)
# ==============================================================================

if ask_step "Restore Configs (Terminator, Wallpapers)"; then
    # Wallpapers
    mkdir -p ~/Pictures/wallp
    [ -d "wallp" ] && cp -r wallp/* ~/Pictures/wallp/
    
    # Terminator
    if [ -f "configs/terminator/config" ]; then
        mkdir -p ~/.config/terminator
        cp configs/terminator/config ~/.config/terminator/config
        echo -e "${GREEN}[OK] Terminator config restored.${NC}"
    else
        echo -e "${YELLOW}[SKIP] Terminator config not found in configs/terminator/${NC}"
    fi
fi

# ==============================================================================
# SECTOR 8: TERMINAL & SHELL ENVIRONMENT SETUP
# ==============================================================================
if ask_step "Configure Terminal Emulator & Shell Environment"; then
    
    # --- HELPER: Starship Preset Loader ---
    apply_starship_preset() {
        local preset_name=$1
        echo -e "${BLUE}[*] Applying Starship Preset: $preset_name${NC}"
        mkdir -p ~/.config
        if command -v starship &> /dev/null; then
            case $preset_name in
                "Pastel (Colorful)") starship preset pastel -o ~/.config/starship.toml ;;
                "Tokyo Night (Dark)") starship preset tokyo-night -o ~/.config/starship.toml ;;
                "Pure (Minimal)") starship preset pure-preset -o ~/.config/starship.toml ;;
                "Gruvbox (Retro)") starship preset gruvbox-rainbow -o ~/.config/starship.toml ;;
                *) echo -e "${YELLOW}[!] Default preset applied.${NC}" ;;
            esac
        fi
    }

    # ==========================================
    # ADIM A: TERMINAL EMULATOR & THEME
    # ==========================================
    echo -e "\n${CYAN}=== TERMINAL EMULATOR SELECTION ===${NC}"
    echo -e "${YELLOW}Which terminal emulator do you want to install/use?${NC}"
    
    term_options=("Terminator (Advanced Tiling)" "Kitty (GPU Accelerated)" "Alacritty (Fastest)" "Gnome-Terminal" "Skip")
    
    select term_opt in "${term_options[@]}"; do
        case $term_opt in
            "Terminator"*)     install_term="terminator" ;;
            "Kitty"*)          install_term="kitty" ;;
            "Alacritty"*)      install_term="alacritty" ;;
            "Gnome-Terminal"*) install_term="gnome-terminal" ;;
            "Skip")            install_term="skip" ;;
            *) echo -e "${RED}Invalid option.${NC}"; continue ;;
        esac
        break
    done

    if [ "$install_term" != "skip" ]; then
        echo -e "${BLUE}[*] Installing $install_term...${NC}"
        if [ "$IS_ARCH" = true ]; then
            sudo pacman -S --noconfirm --needed "$install_term"
        else
            sudo apt-get install -y "$install_term"
        fi
        
        # --- TERMINAL THEME SELECTOR ---
        # 1. KITTY THEMES
        if [ "$install_term" == "kitty" ]; then
            echo -e "\n${CYAN}=== KITTY THEME SELECTION ===${NC}"
            mkdir -p ~/.config/kitty
            [ ! -f ~/.config/kitty/kitty.conf ] && echo "font_family JetBrainsMono Nerd Font" > ~/.config/kitty/kitty.conf

            kitty_themes=("Dracula" "Nord" "Gruvbox Dark" "Tokyo Night" "Cyberpunk" "Skip")
            select k_theme in "${kitty_themes[@]}"; do
                case $k_theme in
                    "Skip") break ;;
                    *)
                        echo -e "${BLUE}[*] Downloading theme: $k_theme...${NC}"
                        theme_slug=$(echo "$k_theme" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')
                        [[ "$theme_slug" == "tokyo-night" ]] && theme_slug="tokyo-night"
                        curl -sS "https://raw.githubusercontent.com/dexpota/kitty-themes/master/themes/${k_theme}.conf" -o ~/.config/kitty/theme.conf
                        if ! grep -q "include ./theme.conf" ~/.config/kitty/kitty.conf; then
                            echo "include ./theme.conf" >> ~/.config/kitty/kitty.conf
                        fi
                        echo -e "${GREEN}[✓] Kitty theme applied.${NC}"
                        break
                        ;;
                esac
            done
        fi

        # 2. ALACRITTY THEMES
        if [ "$install_term" == "alacritty" ]; then
            echo -e "\n${CYAN}=== ALACRITTY THEME SELECTION ===${NC}"
            mkdir -p ~/.config/alacritty
            alac_themes=("Dracula" "Nord" "Gruvbox_Dark" "TokyoNight" "Omni" "Skip")
            select a_theme in "${alac_themes[@]}"; do
                case $a_theme in
                    "Skip") break ;;
                    *)
                        echo -e "${BLUE}[*] Applying theme: $a_theme...${NC}"
                        url="https://raw.githubusercontent.com/alacritty/alacritty-theme/master/themes/${a_theme}.toml"
                        curl -sS "$url" -o ~/.config/alacritty/alacritty.toml
                        echo -e "${GREEN}[✓] Alacritty theme applied.${NC}"
                        break
                        ;;
                esac
            done
        fi
        
        # 3. TERMINATOR CONFIG
        if [ "$install_term" == "terminator" ] && [ -f "configs/terminator/config" ]; then
             echo -e "${BLUE}[*] Applying custom Terminator config...${NC}"
             mkdir -p ~/.config/terminator
             cp configs/terminator/config ~/.config/terminator/config
        fi
    fi

    # ==========================================
    # ADIM B: SHELL (KABUK) SEÇİMİ VE AYARLAR
    # ==========================================
    echo -e "\n${CYAN}=== PREFERRED SHELL & THEME CONFIG ===${NC}"
    echo -e "${YELLOW}Select a shell to configure. If you select your current shell, it will only update the theme.${NC}"
    
    # Mevcut kabuğu tespit et
    CURRENT_SHELL=$(basename "$SHELL")
    echo -e "${DIM}(Current Shell: $CURRENT_SHELL)${NC}"
    
    shell_options=("Zsh (Themes: P10k, Agnoster...)" "Fish (Themes: Starship Presets)" "Bash (Themes: Starship Presets)" "Skip")
    
    select shell_opt in "${shell_options[@]}"; do
        case $shell_opt in
            
            # --- ZSH SETUP ---
            "Zsh"*)
                echo -e "${BLUE}[*] Configure Zsh...${NC}"
                # Install Zsh if missing
                if ! command -v zsh &> /dev/null; then
                    echo -e "${YELLOW}[*] Installing Zsh...${NC}"
                    [ "$IS_ARCH" = true ] && sudo pacman -S --needed --noconfirm zsh git curl || sudo apt-get install -y zsh git curl
                fi

                # Oh-My-Zsh Check
                if [ ! -d "$HOME/.oh-my-zsh" ]; then
                    echo -e "${YELLOW}[*] Installing Oh-My-Zsh...${NC}"
                    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
                fi

                # Plugins Check
                ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
                [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions" ] && git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
                [ ! -d "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting" ] && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"

                # THEME SELECTION (ALWAYS SHOWS)
                echo -e "\n${CYAN}=== ZSH THEME PREVIEW ===${NC}"
                echo -e "1) ${BOLD}agnoster${NC} (Powerline)"
                echo -e "2) ${BOLD}robbyrussell${NC} (Simple)"
                echo -e "3) ${BOLD}bira${NC} (Informative)"
                echo -e "4) ${BOLD}powerlevel10k${NC} (Ultimate)"
                
                read -p "Select Zsh Theme [1-4]: " zsh_theme_choice
                case $zsh_theme_choice in
                    2) SELECTED_THEME="robbyrussell" ;;
                    3) SELECTED_THEME="bira" ;;
                    4) 
                       SELECTED_THEME="powerlevel10k/powerlevel10k"
                       [ ! -d "$ZSH_CUSTOM_DIR/themes/powerlevel10k" ] && git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM_DIR/themes/powerlevel10k"
                       ;;
                    *) SELECTED_THEME="agnoster" ;;
                esac

                # Apply Theme
                if [ -f "$HOME/.zshrc" ]; then
                    sed -i "s|^ZSH_THEME=.*|ZSH_THEME=\"$SELECTED_THEME\"|" "$HOME/.zshrc"
                    sed -i 's/^plugins=(.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
                    echo -e "${GREEN}[✓] .zshrc updated with new theme.${NC}"
                fi

                # SMART CHSH: Sadece kabuk Zsh değilse değiştir
                if [[ "$CURRENT_SHELL" != "zsh" ]]; then
                    echo -e "${YELLOW}[*] Changing default shell to Zsh...${NC}"
                    sudo chsh -s $(which zsh) $USER
                else
                    echo -e "${GREEN}[OK] You are already on Zsh. Only theme updated.${NC}"
                fi
                ;;

            # --- FISH SETUP ---
            "Fish"*)
                echo -e "${BLUE}[*] Configure Fish...${NC}"
                if ! command -v fish &> /dev/null; then
                    [ "$IS_ARCH" = true ] && sudo pacman -S --needed --noconfirm fish || sudo apt-get install -y fish
                fi
                
                if ! command -v starship &> /dev/null; then
                    [ "$IS_ARCH" = true ] && sudo pacman -S --needed --noconfirm starship || curl -sS https://starship.rs/install.sh | sh -s -- -y
                fi

                mkdir -p ~/.config/fish
                if ! grep -q "starship init fish" ~/.config/fish/config.fish 2>/dev/null; then
                    echo "starship init fish | source" >> ~/.config/fish/config.fish
                fi
                
                # THEME SELECTION (ALWAYS SHOWS)
                echo -e "\n${CYAN}=== FISH STARSHIP THEME ===${NC}"
                star_opts=("Pastel (Colorful)" "Tokyo Night (Dark)" "Pure (Minimal)" "Gruvbox (Retro)" "Default")
                select s_opt in "${star_opts[@]}"; do
                    apply_starship_preset "$s_opt"
                    break
                done

                # SMART CHSH
                if [[ "$CURRENT_SHELL" != "fish" ]]; then
                    sudo chsh -s $(which fish) $USER
                else
                    echo -e "${GREEN}[OK] You are already on Fish. Only theme updated.${NC}"
                fi
                ;;

            # --- BASH SETUP ---
            "Bash"*)
                echo -e "${BLUE}[*] Configure Bash...${NC}"
                
                # THEME SELECTION (ALWAYS SHOWS)
                echo -e "\n${CYAN}=== BASH STARSHIP THEME ===${NC}"
                star_opts=("Pastel (Colorful)" "Tokyo Night (Dark)" "Pure (Minimal)" "Gruvbox (Retro)" "Default")
                select s_opt in "${star_opts[@]}"; do
                    # Starship install if needed
                    if ! command -v starship &> /dev/null; then
                         [ "$IS_ARCH" = true ] && sudo pacman -S --needed --noconfirm starship || curl -sS https://starship.rs/install.sh | sh -s -- -y
                    fi
                    
                    if ! grep -q "starship init bash" ~/.bashrc; then
                         echo 'eval "$(starship init bash)"' >> ~/.bashrc
                    fi

                    apply_starship_preset "$s_opt"
                    break
                done

                # SMART CHSH
                if [[ "$CURRENT_SHELL" != "bash" ]]; then
                    sudo chsh -s $(which bash) $USER
                else
                    echo -e "${GREEN}[OK] You are already on Bash. Only theme updated.${NC}"
                fi
                ;;

            "Skip")
                echo -e "${YELLOW}[SKIP] Keeping current shell.${NC}"
                ;;
            *) echo -e "${RED}Invalid option.${NC}"; continue ;;
        esac
        break
    done
    
    # --- FONT CHECK (SILENT IF INSTALLED) ---
    if [ "$IS_ARCH" = true ]; then
        if ! pacman -Qi ttf-jetbrains-mono-nerd &>/dev/null; then
             echo -e "${BLUE}[*] Installing JetBrainsMono Nerd Font (Required for icons)...${NC}"
             sudo pacman -S --noconfirm --needed ttf-jetbrains-mono-nerd
        fi
    else
        if command -v fc-list &>/dev/null && ! fc-list | grep -q "JetBrainsMono Nerd Font"; then
             echo -e "${YELLOW}[!] NOTICE: Ensure 'JetBrainsMono Nerd Font' is installed for icons.${NC}"
        fi
    fi
fi

# ==============================================================================
# 9. SECURITY & OPTIMIZATIONS (ULTIMATE EDITION)
# ==============================================================================

if ask_step "Apply Security & System Optimizations"; then
    
    # 1. ÖN HAZIRLIK: Eksik Güvenlik Araçlarını Kontrol Et ve Kur
    echo -e "\n${BLUE}[*] Checking security tools...${NC}"
    declare -a sec_tools=("arch-audit" "clamav" "rkhunter" "lynis" "firejail" "nethogs")
    for tool in "${sec_tools[@]}"; do
        if ! pacman -Qi "$tool" &>/dev/null; then
            echo -e "${YELLOW}[!] Missing tool: $tool. Installing...${NC}"
            sudo pacman -S --noconfirm "$tool" &>/dev/null
        fi
    done

    # 2. KONFİGÜRASYON ADIMLARI (Progress Bar ile)
    declare -a opt_steps=(
        "SSD TRIM (fstrim)"
        "Bluetooth Auto-Enable"
        "Firewall (UFW)"
        "ZRAM (Memory Swap)"
        "ClamAV (Update DB)"
        "Rkhunter (Update DB)"
        "Firejail (Sandbox All)"
        "Arch Cleanup"
    )
    
    total_steps=${#opt_steps[@]}
    current_step=0
    
    print_opt_bar() {
        local current=$1
        local total=$2
        local task_name=$3
        local width=40 
        local percent=$((current * 100 / total))
        local filled=$((percent * width / 100))
        local empty=$((width - filled))
        local bar_fill=$(printf "%0.s█" $(seq 1 $filled))
        local bar_empty=$(printf "%0.s░" $(seq 1 $empty))
        
        clear
        echo -e "${BLUE}=========================================${NC}"
        echo -e "${GREEN}      System Optimization Progress       ${NC}"
        echo -e "${BLUE}=========================================${NC}"
        echo -e "${BOLD}[${GREEN}${bar_fill}${GRAY}${bar_empty}${NC}${BOLD}] ${percent}%${NC}"
        echo -e "Configuring: ${CYAN}${task_name}${NC}"
        echo -e "${DIM}-----------------------------------------${NC}"
    }

    for step in "${opt_steps[@]}"; do
        ((current_step++))
        print_opt_bar $current_step $total_steps "$step"
        sleep 0.5 

        case $step in
            "SSD TRIM (fstrim)")
                sudo systemctl enable --now fstrim.timer 2>/dev/null ;;
                
            "Bluetooth Auto-Enable")
                if [ -f /etc/bluetooth/main.conf ]; then
                    sudo sed -i 's/#AutoEnable=true/AutoEnable=true/g' /etc/bluetooth/main.conf
                    sudo systemctl enable --now bluetooth 2>/dev/null
                fi ;;
                
            "Firewall (UFW)")
                if command -v ufw &> /dev/null; then
                    sudo ufw default deny incoming
                    sudo ufw default allow outgoing
                    echo "y" | sudo ufw enable
                fi ;;
                
            "ZRAM (Memory Swap)")
                if pacman -Qi zram-generator &>/dev/null; then
                    if [ ! -f /etc/systemd/zram-generator.conf ]; then
                        echo -e "[zram0]\nzram-size = min(ram, 8192)\ncompression-algorithm = zstd" | sudo tee /etc/systemd/zram-generator.conf > /dev/null
                    fi
                    sudo systemctl daemon-reload
                    sudo systemctl start systemd-zram-setup@zram0.service
                fi ;;
                
            "ClamAV (Update DB)")
                if pacman -Qi clamav &>/dev/null; then
                    sudo systemctl stop clamav-freshclam 2>/dev/null
                    sudo freshclam 2>/dev/null
                    sudo systemctl enable --now clamav-freshclam
                fi ;;
                
            "Rkhunter (Update DB)")
                if command -v rkhunter &>/dev/null; then
                    sudo rkhunter --propupd 2>/dev/null
                fi ;;
                
            "Firejail (Sandbox Integration)")
                if command -v firecfg &>/dev/null; then
                    sudo firecfg 2>/dev/null
                fi ;;
                
            "Arch Cleanup")
                if [ "$IS_ARCH" = true ]; then
                    sudo pacman -Rns $(pacman -Qdtq) --noconfirm 2>/dev/null
                    sudo pacman -Sc --noconfirm 2>/dev/null
                fi ;;
        esac
    done

    # 3. GÖRSEL BİLGİ TABLOSU (DASHBOARD)
    echo -e "\n${BLUE}╔═════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           SECURITY & TOOLS DASHBOARD                ║${NC}"
    echo -e "${BLUE}╠═════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} ${BOLD}TOOL${NC}          ${BLUE}║${NC} ${BOLD}FUNCTION${NC}                            ${BLUE}║${NC}"
    echo -e "${BLUE}╠═══════════════╬═════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Arch-Audit${NC}    ${BLUE}║${NC} Vulnerability Scanner (CVE Check)   ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Lynis${NC}         ${BLUE}║${NC} System Hardening & Audit Tool       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}ClamAV${NC}        ${BLUE}║${NC} Antivirus Engine                    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Rkhunter${NC}      ${BLUE}║${NC} Rootkit & Backdoor Hunter           ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Firejail${NC}      ${BLUE}║${NC} Application Sandboxing              ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} ${CYAN}Nethogs${NC}       ${BLUE}║${NC} Per-App Network Traffic Monitor     ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════╩═════════════════════════════════════╝${NC}"
    
    # 4. AKTİF TARAMA MODU (User Prompt)
    echo -e "\n${YELLOW}[?] Would you like to run a comprehensive security scan now?${NC}"
    echo -e "${DIM}(This will run Arch-Audit, Lynis, ClamAV Home Scan, and Rootkit Hunter sequentially)${NC}"
    
    if ask_step "Start Security Scans"; then
        
        # A) ARCH AUDIT
        echo -e "\n${MAGENTA}>>> Running Arch-Audit (Package Vulnerabilities)...${NC}"
        if command -v arch-audit &>/dev/null; then
            arch-audit
        else
            echo -e "${RED}[!] Arch-Audit not found.${NC}"
        fi
        sleep 2

        # B) LYNIS
        echo -e "\n${MAGENTA}>>> Running Lynis (System Audit)...${NC}"
        echo -e "${DIM}(Running in quick mode...)${NC}"
        if command -v lynis &>/dev/null; then
            sudo lynis audit system --quick
        fi
        echo -e "${GREEN}[✓] Lynis audit finished.${NC}"
        sleep 2

        # C) CLAMAV
        echo -e "\n${MAGENTA}>>> Running ClamAV (Home Directory Scan)...${NC}"
        echo -e "${DIM}(Scanning all files in /home/$USER. This enables detailed output...)${NC}"
        if command -v clamscan &>/dev/null; then
            # DEĞİŞİKLİK: '-i' kaldırıldı, artık her dosyayı gösterir.
            clamscan -r -i /home/$USER --bell
            echo -e "${GREEN}[✓] ClamAV scan finished.${NC}"
        fi
        sleep 2

        # D) ROOTKIT HUNTER
        echo -e "\n${MAGENTA}>>> Running Rkhunter (Rootkit Check)...${NC}"
        if command -v rkhunter &>/dev/null; then
            # --sk (skip keypress): Beklemeden geçer ama bölümleri ekrana yazar
            # --enable all: Emin olmak için tüm testleri açar (Opsiyonel, standart tarama genelde yeterlidir)
            sudo rkhunter --check --sk
        fi
        echo -e "${GREEN}[✓] All security scans completed.${NC}"
    else
        echo -e "${YELLOW}[!] Security scans skipped. You can run them manually later.${NC}"
    fi
    # ==============================================================================
    # 5. AUDIT FIX & HARDENING (Post-Scan Patches)
    # ==============================================================================
    
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          AUDIT FIX & SYSTEM HARDENING                ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} Based on the scan results, the following actions    ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC} are recommended to secure your system:              ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${BOLD}Proposed Action Plan:${NC}"
    echo -e "   ${CYAN}1. System Update:${NC}      Fix 'High Risk' vulnerabilities found by Arch-Audit."
    echo -e "   ${CYAN}2. Kernel Hardening:${NC}   Apply 'sysctl' rules to restrict access to kernel logs & pointers."
    echo -e "   ${CYAN}3. SSH Hardening:${NC}      Disable Root login and Password auth (Key-only)."
    echo -e "   ${CYAN}4. Network Security:${NC}   Prevent IP spoofing and redirect attacks."
    
    if ask_step "Apply All Hardening Fixes"; then
        echo -e "\n${BLUE}[*] Applying security patches...${NC}"
        
        # 1. SİSTEM GÜNCELLEMESİ (Kritik Açıklar İçin)
        echo -e "   -> Updating System (Pacman)..."
        if [ "$IS_ARCH" = true ]; then
            sudo pacman -Syu --noconfirm
            echo -e "${GREEN}[✓] System updated. Vulnerabilities patched.${NC}"
        else
            echo -e "${YELLOW}[!] Skipping update (Not Arch Linux).${NC}"
        fi

        # 2. KERNEL & NETWORK HARDENING (Sysctl)
        echo -e "   -> Applying Kernel & Network Hardening..."
        # Güvenli konfigürasyon dosyasını oluştur
        cat <<EOF | sudo tee /etc/sysctl.d/99-security.conf > /dev/null
# KERNEL SECURITY
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
fs.protected_fifos = 2
fs.protected_regular = 2

# NETWORK SECURITY
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
EOF
        # Ayarları yükle
        sudo sysctl --system > /dev/null 2>&1
        echo -e "${GREEN}[✓] Kernel parameters hardened (sysctl applied).${NC}"

        # 3. SSH HARDENING
        echo -e "   -> Hardening SSH Configuration..."
        if [ -f /etc/ssh/sshd_config ]; then
            # Yedek al
            sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
            
            # A) Root girişini kapat (Bu her senaryoda güvenlidir)
            sudo sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            sudo sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
            echo -e "${GREEN}[✓] SSH Root login disabled.${NC}"
            
            # B) Şifreli Girişi Kapatma Sorusu (Key-Only Access)
            echo -e "\n${YELLOW}[?] Advanced: Disable SSH Password Authentication? (Key-only access)${NC}"
            echo -e "${RED}[WARNING] Do NOT enable this if you haven't added your SSH Public Key to the server yet!${NC}"
            echo -e "${DIM}          (If you don't know what this is, say 'n')${NC}"

            if ask_step "Disable Password Authentication"; then
                sudo sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                sudo sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                echo -e "${GREEN}[✓] Password Authentication disabled (Secure Mode).${NC}"
            else
                echo -e "${YELLOW}[!] Password Authentication kept enabled (Compatibility Mode).${NC}"
            fi
            
            # Servisi yeniden başlat (Hata vermemesi için kontrol et)
            if systemctl is-active --quiet sshd; then
                sudo systemctl restart sshd
            fi
        else
            echo -e "${YELLOW}[!] SSH config not found. Skipping.${NC}"
        fi
    # ==============================================================================
    # 6. HARDENED MODE (Advanced Traffic & Physical Security)
    # ==============================================================================
    
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                HARDENED MODE ACTIVATION              ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    
    echo -e "${YELLOW}[?] Do you want to enable 'Hardened Mode' (OpenSnitch + USBGuard)?${NC}"
    echo -e "\n${BOLD}About This Module:${NC}"
    
    # OpenSnitch Bilgisi
    echo -e "${CYAN}1. OpenSnitch (Application Firewall):${NC}"
    echo -e "   ${GREEN}[+] Pros:${NC} Blocks apps from phoning home, detects spyware/telemetry."
    echo -e "   ${RED}[-] Cons:${NC} Frequent pop-ups initially (You must allow/deny connections)."
    
    # USBGuard Bilgisi
    echo -e "${CYAN}2. USBGuard (Physical Port Security):${NC}"
    echo -e "   ${GREEN}[+] Pros:${NC} Prevents BadUSB attacks. Blocks unauthorized USB devices."
    echo -e "   ${RED}[-] Cons:${NC} New USB drives won't work until you manually allow them."
    
    echo -e "\n${DIM}Recommended for: High-threat environments or privacy enthusiasts.${NC}"

    if ask_step "Activate Hardened Mode"; then
        echo -e "\n${BLUE}[*] Installing Hardened Mode tools...${NC}"
        
        # OpenSnitch Kurulumu
        if [ "$IS_ARCH" = true ]; then
            echo -e "   -> Installing OpenSnitch..."
            # opensnitch-git bazen daha günceldir ama standart paket daha kararlıdır
            yay -S --needed --noconfirm opensnitch opensnitch-ui
            
            # Servisi aktif et
            sudo systemctl enable --now opensnitchd
            
            # Arayüzü (GUI) başlangıça ekle
            mkdir -p ~/.config/autostart
            cp /usr/share/applications/opensnitch_ui.desktop ~/.config/autostart/ 2>/dev/null
            echo -e "${GREEN}[✓] OpenSnitch active. Watch for pop-ups!${NC}"
        fi

        # USBGuard Kurulumu
        echo -e "   -> Installing USBGuard..."
        if [ "$IS_ARCH" = true ]; then
            sudo pacman -S --needed --noconfirm usbguard
            
            # Mevcut takılı cihazlara izin ver (Yoksa klavye/mouse kilitlenir!)
            echo -e "${YELLOW}[!] Whitelisting currently connected USB devices...${NC}"
            sudo usbguard generate-policy | sudo tee /etc/usbguard/rules.conf > /dev/null
            
            # Servisi başlat
            sudo systemctl enable --now usbguard
            echo -e "${GREEN}[✓] USBGuard active. New devices are now BLOCKED by default.${NC}"
            echo -e "${DIM}    (To allow a new device, use: 'sudo usbguard list-devices' and 'allow-device')${NC}"
        fi
        
    else
        echo -e "${YELLOW}[!] Hardened Mode skipped. Standard security applied.${NC}"
    		fi
	fi
fi

# ==============================================================================
# SECTOR 10: FINAL SUMMARY
# ==============================================================================

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}          INSTALLATION SUMMARY           ${NC}"
echo -e "${BLUE}=========================================${NC}"

# --- DYNAMIC STATUS CHECKS ---
# 1. BlackArch Durumu
if grep -q "^\[blackarch\]" /etc/pacman.conf 2>/dev/null; then
    ba_status="${GREEN}Active${NC}"
else
    ba_status="${DIM}Inactive${NC}"
fi

# 2. Hyprland Durumu
if pacman -Qi hyprland &>/dev/null; then 
    hypr_status="${GREEN}Installed${NC}"
else 
    hypr_status="${DIM}Skipped${NC}"
fi

# 3. Security Hardening Durumu (Dosya kontrolü)
if [ -f /etc/sysctl.d/99-security.conf ]; then
    sec_status="${GREEN}Applied (Hardened)${NC}"
else
    sec_status="${YELLOW}Standard${NC}"
fi

# 4. Hardened Mode (Servis kontrolü)
if systemctl is-active --quiet opensnitchd || systemctl is-active --quiet usbguard; then
    hard_status="${GREEN}Active (Zırhlı)${NC}"
else
    hard_status="${DIM}Disabled${NC}"
fi

# 5. Gaming Mode (Paket kontrolü)
if pacman -Qi gamemode &>/dev/null; then
    gamemode_status="${GREEN}Ready${NC}"
else
    gamemode_status="${DIM}Skipped${NC}"
fi

# --- REPORT ---
echo -e "OS Type:           $OS"
echo -e "Base System:       ${base_done:-${GREEN}Checked${NC}}"
echo -e "BlackArch Repo:    $ba_status"
echo -e "Packages:          ${GREEN}Processed${NC}"
echo -e "GNOME Config:      ${gnome_done:-${DIM}Skipped${NC}}"
echo -e "Gaming Mode:       $gamemode_status"
echo -e "Hyprland Env:      $hypr_status"
echo -e "Shell & Term:      ${GREEN}Configured${NC}"
echo -e "Security Audit:    $sec_status"
echo -e "Hardened Mode:     $hard_status"
echo -e "GPU Driver:        ${GREEN}${gpu:-None}${NC}"
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}Installation complete!${NC}\n"

# ==============================================================================
# FINAL CLEANUP SECTION 
# ==============================================================================

echo -e "\n${BLUE}========== POST-INSTALLATION CLEANUP ==========${NC}"

if ask_step "Do you want to remove unnecessary leftovers (orphans, cache, temp files)"; then
    echo -e "${YELLOW}[*] Starting system maintenance...${NC}"

    # 1. Yetim Paketleri Kaldır (Removing orphaned packages)
    # Yetim paket: Başka hiçbir paket tarafından ihtiyaç duyulmayan, sistemde gereksiz yer kaplayan paketlerdir.
    if [ -n "$(pacman -Qtdq)" ]; then
        echo -e "${BLUE}[*] Removing orphaned packages (Yetim paketler)...${NC}"
        sudo pacman -Rns $(pacman -Qtdq) --noconfirm
    else
        echo -e "${BLUE}[SKIP] No orphaned packages found.${NC}"
    fi

    # 2. Pacman Önbelleğini Temizle (Clearing package cache)
    # İndirilen .pkg.tar.zst dosyalarını silerek disk alanı açar.
    echo -e "${BLUE}[*] Clearing pacman cache (Paket önbelleği)...${NC}"
    sudo pacman -Scc --noconfirm

    # 3. Geçici Dosyaları Temizle (Cleanup leftovers)
    # Eğer script sırasında indirilen strap.sh veya geçici loglar kaldıysa siler.
    [ -f "strap.sh" ] && rm strap.sh
    
    echo -e "${GREEN}[OK] System is lean and clean.${NC}"
else
    echo -e "${YELLOW}[SKIP] Skipping cleanup. Leftovers preserved.${NC}"
fi

# --- AUTO-REBOOT OPTION ---
echo -e "${YELLOW}[!] System reboot is recommended to apply all changes.${NC}"
if ask_step "Reboot system now"; then
    echo -e "${BLUE}[*] Rebooting in 5 seconds... (Press Ctrl+C to cancel)${NC}"
    sleep 5
    sudo reboot
else
    echo -e "${GREEN}[*] Remember to reboot manually later: sudo reboot${NC}"
fi
