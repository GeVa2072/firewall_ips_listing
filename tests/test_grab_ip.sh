#!/usr/bin/env bash
set -euo pipefail

# Get the directory of the repo root (core.func lives one level above tests/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source the function file safely
if [ -f "$SCRIPT_DIR/core.func" ]; then
    source "$SCRIPT_DIR/core.func"
else
    echo "Error: core.func not found." >&2
    exit 1
fi

grab_ip_test_ip() {
  text=$1
  ip=$2
  type=$3
  expected=${4:-VALID} # Par défaut 'VALID' si le 4ème paramètre est omis
  
  total=$((total + 1))
   
  if ([ "$expected" = "VALID" ] && grab_ip_is_valid_ip "$ip" "$type") || \
     ([ "$expected" = "INVALID" ] && ! grab_ip_is_valid_ip "$ip" "$type")
  then
    grab_ip_print_status_line "${text}" "${ip}" "${GREEN}SUCCESS${NC}"
	success=$((success + 1))
  else
    grab_ip_print_status_line "${text}" "${ip}" "${RED}FAILED ${NC}"
	failed=$((failed + 1))
  fi
}

# Initialisation des compteurs
total=0
success=0
failed=0

# test resolv IPV6 valid
grab_ip_print_header "📊 RAPPORT DE CONFORMITÉ IPV6 : SCÉNARIOS \$status"
grab_ip_test_ip "Adresse complète standard : Huit groupes hexadécimaux complets" \
 2001:0db8:85a3:0000:0000:8a2e:0370:7334 AAAA
grab_ip_test_ip "Zéro unique : Remplacement des blocs de zéros par un seul zéro" \
 2001:db8:85a3:0:0:8a2e:370:7334 AAAA 
grab_ip_test_ip "Compression double deux-points : Utilisation du :: pour une suite de zéros" \
 2001:db8:85a3::8a2e:370:7334 AAAA 
grab_ip_test_ip "Compression au début : Zéros initiaux compressés" \
 ::1 AAAA 
grab_ip_test_ip "Compression à la fin : Zéros finaux compressés" \
 2001:db8:: AAAA 
grab_ip_test_ip "Lettres majuscules/minuscules : Vérifier l'insensibilité à la casse" \
2001:DB8:A8B::1 AAAA 
grab_ip_test_ip "Adresse IPv4 mappée : Format mixte pour la transition" \
 ::ffff:192.168.1.1 AAAA 
grab_ip_test_ip "Adresse avec identifiant de zone" \
 fe80::1%eth0 AAAA 

grab_ip_test_ip "Double compression : Interdire deux fois le double deux-points" \
 2001::85a3::7334 AAAA "INVALID"
grab_ip_test_ip "Groupes trop longs : Plus de 4 caractères hexadécimaux dans un groupe" \
 2001:0db88:85a3::1 AAAA "INVALID"
grab_ip_test_ip "Trop de groupes : Plus de 8 groupes après expansion" \
 2001:0db8:85a3:0000:0000:8a2e:0370:7334:1234 AAAA "INVALID"
grab_ip_test_ip "Pas assez de groupes : Moins de 8 groupes sans compression ::" \
 2001:db8:85a3:0:8a2e:370 AAAA "INVALID"

# test resolv IPV4 valid
grab_ip_print_header "📊 RAPPORT DE CONFORMITÉ IPV4 : SCÉNARIOS \$status"
grab_ip_test_ip "Adresse IPv4 standard" \
 192.168.1.1 A
grab_ip_test_ip "Adresse IPv4 avec zéros" \
 10.0.0.1 A
grab_ip_test_ip "Adresse IPv4 borne maximale 255" \
 255.255.255.255 A
grab_ip_test_ip "Adresse IPv4 borne minimale 0" \
 0.0.0.0 A

grab_ip_test_ip "Octet supérieur à 255" \
 192.168.1.256 A "INVALID"
grab_ip_test_ip "Octet à trois chiffres hors bornes" \
 999.1.1.1 A "INVALID"
grab_ip_test_ip "Trop peu d'octets" \
 192.168.1 A "INVALID"
grab_ip_test_ip "Trop d'octets" \
 192.168.1.1.1 A "INVALID"
grab_ip_test_ip "Caractère non numérique" \
 192.168.1.a A "INVALID"

grab_ip_print_footer ${total} ${success} ${failed}

