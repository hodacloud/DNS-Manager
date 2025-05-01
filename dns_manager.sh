#!/bin/bash
# HodaCloud DNS Manager v3.0
# Author: hodacloud.com
# Usage: sudo ./dns_manager.sh

# Configuration
LOG_DIR="/var/log/dns_monitor"
PCAP_FILE="$LOG_DIR/dns_capture.pcap"
LIVE_LOG="$LOG_DIR/live.log"
HISTORY_LOG="$LOG_DIR/history.log"
DOMAIN_COUNTS="$LOG_DIR/domain_counts.log"
BLOCKLIST_FILE="$LOG_DIR/blocklist.conf"

# Color Scheme
R="\033[1;31m"  # Red
G="\033[1;32m"  # Green
Y="\033[1;33m"  # Yellow
B="\033[1;34m"  # Blue
M="\033[1;35m"  # Magenta
C="\033[1;36m"  # Cyan
W="\033[1;37m"  # White
NC="\033[0m"    # No Color

# Box Drawing Characters
TL="${C}╔$(printf '═%.0s' {1..58})╗${NC}"
TR="${C}║${NC}"
BL="${C}╚$(printf '═%.0s' {1..58})╝${NC}"
SP="${C}║${NC}"
HB="${C}╠$(printf '─%.0s' {1..58})╣${NC}"

# Initialize system
initialize_system() {
    mkdir -p "$LOG_DIR"
    touch "$LIVE_LOG" "$HISTORY_LOG" "$DOMAIN_COUNTS" "$BLOCKLIST_FILE"
    chmod 700 "$LOG_DIR"
    echo -e "\n${G}✓ System initialized successfully!"
    sleep 1
}

# Cleanup function
cleanup() {
    pkill -P $$ 2>/dev/null
    rm -f "$LIVE_LOG"
}

# Update domain counts
update_domain_count() {
    domain=$1
    touch "$DOMAIN_COUNTS"
    awk -v dom="$domain" '
    BEGIN {FS=OFS=" "}
    $1 == dom {found=1; $2++}
    {print}
    END {if (!found) print dom, 1}
    ' "$DOMAIN_COUNTS" > tmp && mv tmp "$DOMAIN_COUNTS"
}

# Capture DNS queries
capture_dns() {
    stdbuf -oL tshark -i any -f "udp port 53" -l \
        -T fields -e frame.time -e ip.src -e dns.qry.name \
        -Y "dns.flags.response == 0" \
        -E header=n -E separator="|" -E quote=n 2>/dev/null | \
    while read -r line; do
        timestamp=$(echo "$line" | cut -d'|' -f1)
        src_ip=$(echo "$line" | cut -d'|' -f2)
        domain=$(echo "$line" | cut -d'|' -f3)
        
        domain_lower=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
        if grep -qxi "^$domain_lower$" "$BLOCKLIST_FILE"; then
            continue
        fi

        if [[ -n "$domain" && ! "$domain" =~ ^[0-9.]+$ ]]; then
            echo "$timestamp|$src_ip|$domain" >> "$LIVE_LOG"
            echo "$timestamp|$src_ip|$domain" >> "$HISTORY_LOG"
            update_domain_count "$domain"
        fi
    done
}

# Live display
live_display() {
    echo -e "\n${TL}"
    echo -e "${TR} ${B}»»» Live DNS Query Monitoring ««« ${W}Press ${R}Ctrl+C ${W}to stop   ${C}║${NC}"
    echo -e "${HB}"
    tail -f "$LIVE_LOG" | awk -F\| '
    {
        printf "║ \033[1;36m%-20s \033[1;33m%-15s \033[1;32m%-35s\033[0m ║\n", 
        $1, $2, $3
    }'
    echo -e "${BL}"
}

# Show statistics
show_statistics() {
    echo -e "\n${TL}"
    echo -e "${TR} ${M}»»» DNS Query Statistics ««« ${W}Sorted by query count.      ${C}║${NC}"
    echo -e "${HB}"
    awk '{print $2 " " $1}' "$DOMAIN_COUNTS" | sort -nr -k1 | awk '
    BEGIN {printf "║ \033[1;35m%-10s \033[1;34m%-45s\033[0m ║\n", "COUNT", "DOMAIN"}
    {printf "║ \033[1;32m%-10s \033[1;36m%-45s\033[0m ║\n", $1, $2}'
    echo -e "${BL}\n"
}

# Block domain
block_domain() {
    echo -e "\n${TL}"
    echo -e "${TR} ${R}»»» Domain Blocking System ««« ${W}Enter domain to block.    ${C}║${NC}"
    echo -e "${HB}"
    echo -en "║ ${C}Enter domain: ${NC}"
    read domain
    domain_lower=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
    
    if grep -qxi "^$domain_lower$" "$BLOCKLIST_FILE"; then
        echo -e "║ ${R}✗ Domain already blocked!${NC} ${C}                               ║${NC}"
    else
        echo "$domain_lower" >> "$BLOCKLIST_FILE"
        echo -e "║ ${G}✓ Domain '${Y}$domain${G}' blocked!${NC} ${C}                     ║$${NC}"
    fi
    echo -e "${BL}"
    sleep 1
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "${TL}"
        echo -e "${TR}             ${C}HodaCloud ${W}DNS Manager ${G}v8.0 ${C}                  ║${NC}"
        echo -e "${HB}"
        echo -e "${TR} ${G}1.${W} Initialize System                                     ${C}║${NC}"
        echo -e "${TR} ${G}2.${W} Start DNS Monitoring                                  ${C}║${NC}"
        echo -e "${TR} ${G}3.${W} Show Statistics                                       ${C}║${NC}"
        echo -e "${TR} ${G}4.${W} Block Domain                                          ${C}║${NC}"
        echo -e "${TR} ${R}5.${W} Exit                                                  ${C}║${NC}"
        echo -e "${BL}"
        echo -en " ║ ${C}Enter your choice [1-5]: ${NC}"
        read choice
        
        case $choice in
            1)
                initialize_system
                read -p " ║ Press Enter to continue..." _
                ;;
            2)
                if [[ ! -d "$LOG_DIR" ]]; then
                    echo -e " ║ ✗ Please initialize first!${NC} ║"
                    read -p " ║ Press Enter to continue..." _
                    continue
                fi
                trap cleanup SIGINT
                rm -f "$LIVE_LOG"
                touch "$LIVE_LOG"
                capture_dns &
                live_display &
                wait
                ;;
            3)
                show_statistics
                read -p " ║ Press Enter to continue..." _
                ;;
            4)
                block_domain
                read -p " ║ Press Enter to continue..." _
                ;;
            5)
                cleanup
                clear
                echo -e "\n${TL}"
                echo -e "${TR} ${G}       Thank you for using HodaCloud DNS Manager!        ${C}║${NC}"
                echo -e "${TR} ${C}             Visit us at: ${M}hodacloud.com                  ${C}║${NC}"
                echo -e "${BL}\n"
                exit 0
                ;;
            *)
                echo -e " ║ ${R}✗ Invalid choice!${NC} ${C}║${NC}"
                sleep 1
                ;;
        esac
    done
}

# Start script
main_menu
