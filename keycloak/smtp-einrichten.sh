#!/bin/bash
# =============================================================================
# Keycloak-Realm aus der .env einrichten: Sprache, Mailtexte und SMTP
# =============================================================================
#
# Läuft einmal nach dem Start von Keycloak (Dienst "keycloak-mail" in
# compose.yml). Mehrfaches Ausführen ist unkritisch – die Werte werden jedes
# Mal überschrieben.
#
# 1. Sprache: nur Deutsch, Anzeigename = FOODCOOP_NAME. Damit sind
#    Anmeldeseite, "Passwort festlegen" und die Keycloak-Mails deutsch.
#
# 2. Eigene Texte für die Einladungs-Mail ("Update your account"), die beim
#    Anlegen eines Benutzers bzw. über "E-Mail senden" verschickt wird.
#    Gültigkeit des Links: KEYCLOAK_LINK_GUELTIG_STUNDEN (Standard 72).
#
# 3. SMTP: dieselben Daten, die auch das Backend nutzt – für "Passwort
#    vergessen", Einladungs-Mails und die Bestätigung der E-Mail-Adresse.
#    Ist SPRING_MAIL_HOST leer, wird SMTP übersprungen.
#
#      Port 587 -> STARTTLS (empfohlen)
#      Port 465 -> SSL
#
# =============================================================================

set -euo pipefail

KCADM=/opt/keycloak/bin/kcadm.sh

SERVER="http://keycloak:${KEYCLOAK_PORT_INTERNAL:-8080}${KC_HTTP_RELATIVE_PATH:-}"

NAME="${FOODCOOP_NAME:-FoodCoop}"

LINK_STUNDEN="${KEYCLOAK_LINK_GUELTIG_STUNDEN:-72}"


# kcadm liest Werte als JSON, wenn sie danach aussehen (Zahlen, true, {...}).
# Keycloak erwartet für SMTP aber Text – daher alles als JSON-String übergeben.
text() {
    local wert="$1"
    wert="${wert//\\/\\\\}"
    wert="${wert//\"/\\\"}"
    printf '"%s"' "$wert"
}


echo "[keycloak-mail] Anmelden an ${SERVER} ..."

"$KCADM" config credentials \
    --config /tmp/kcadm.config \
    --server "$SERVER" \
    --realm master \
    --user "$KEYCLOAK_ADMIN" \
    --password "$KEYCLOAK_ADMIN_PASSWORD"


# -----------------------------------------------------------------------------
# 1. Sprache und Name
# -----------------------------------------------------------------------------

echo "[keycloak-mail] Realm ${KEYCLOAK_REALM}: Sprache Deutsch, Name \"${NAME}\", Links ${LINK_STUNDEN} Std. gültig ..."

"$KCADM" update "realms/${KEYCLOAK_REALM}" \
    --config /tmp/kcadm.config \
    -s "displayName=$(text "${NAME}")" \
    -s 'internationalizationEnabled=true' \
    -s 'supportedLocales=["de"]' \
    -s 'defaultLocale="de"' \
    -s "actionTokenGeneratedByAdminLifespan=$(( LINK_STUNDEN * 3600 ))"


# -----------------------------------------------------------------------------
# 2. Texte der Einladungs-Mail
# -----------------------------------------------------------------------------
#
# Platzhalter von Keycloak:
#   {0} Link   {2} Name der Foodcoop   {3} was zu tun ist   {4} Gültigkeit
#
# Keine einfachen Anführungszeichen (') verwenden – Keycloak würde sie
# als Steuerzeichen lesen.

NAME_JSON="$(text "${NAME}")"
NAME_JSON="${NAME_JSON:1:${#NAME_JSON}-2}"

cat > /tmp/texte-de.json <<JSON
{
  "executeActionsSubject": "Dein Zugang bei ${NAME_JSON}",
  "executeActionsBody": "Hallo,\n\nfür dein Konto bei {2} ist noch etwas zu tun: {3}.\n\nÜber diesen Link geht es los:\n\n{0}\n\nDer Link ist {4} lang gültig. Danach kann dir ein Admin einen neuen schicken.\n\nWenn du mit dieser Mail nichts anfangen kannst, ignoriere sie einfach – es wird nichts geändert.\n\nViele Grüße\n{2}",
  "executeActionsBodyHtml": "<p>Hallo,</p><p>für dein Konto bei <strong>{2}</strong> ist noch etwas zu tun: <strong>{3}</strong>.</p><p><a href=\"{0}\">Hier geht es los</a></p><p>Der Link ist {4} lang gültig. Danach kann dir ein Admin einen neuen schicken.</p><p>Wenn du mit dieser Mail nichts anfangen kannst, ignoriere sie einfach – es wird nichts geändert.</p><p>Viele Grüße<br>{2}</p>",
  "requiredAction.UPDATE_PASSWORD": "Passwort festlegen",
  "requiredAction.VERIFY_EMAIL": "E-Mail-Adresse bestätigen",
  "requiredAction.UPDATE_PROFILE": "Profil vervollständigen",
  "requiredAction.CONFIGURE_TOTP": "Zwei-Faktor-Anmeldung einrichten"
}
JSON

echo "[keycloak-mail] Texte der Einladungs-Mail setzen ..."

"$KCADM" create "realms/${KEYCLOAK_REALM}/localization/de" \
    --config /tmp/kcadm.config \
    -f /tmp/texte-de.json


# -----------------------------------------------------------------------------
# 3. SMTP
# -----------------------------------------------------------------------------

if [ -z "${SPRING_MAIL_HOST:-}" ]; then
    echo "[keycloak-mail] SPRING_MAIL_HOST ist leer – SMTP wird nicht eingerichtet."
    echo "[keycloak-mail] Fertig."
    exit 0
fi

ABSENDER="${MAIL_FROM:-${SPRING_MAIL_USERNAME:-}}"

if [ -z "$ABSENDER" ]; then
    echo "[keycloak-mail] Weder MAIL_FROM noch SPRING_MAIL_USERNAME gesetzt – ohne Absender verschickt Keycloak keine Mails." >&2
    exit 1
fi

ANZEIGENAME="${MAIL_FROM_NAME:-${NAME}}"

PORT="${SPRING_MAIL_PORT:-587}"

if [ "$PORT" = "465" ]; then
    SSL=true
    STARTTLS=false
else
    SSL=false
    STARTTLS="${SPRING_MAIL_SMTP_STARTTLS_ENABLE:-true}"
fi

AUTH="${SPRING_MAIL_SMTP_AUTH:-true}"

echo "[keycloak-mail] SMTP für Realm ${KEYCLOAK_REALM} setzen (${SPRING_MAIL_HOST}:${PORT}, SSL=${SSL}, StartTLS=${STARTTLS}, Absender ${ABSENDER}) ..."

"$KCADM" update "realms/${KEYCLOAK_REALM}" \
    --config /tmp/kcadm.config \
    -s "smtpServer.host=$(text "${SPRING_MAIL_HOST}")" \
    -s "smtpServer.port=$(text "${PORT}")" \
    -s "smtpServer.from=$(text "${ABSENDER}")" \
    -s "smtpServer.fromDisplayName=$(text "${ANZEIGENAME}")" \
    -s "smtpServer.replyTo=$(text "${MAIL_REPLY_TO:-}")" \
    -s "smtpServer.auth=$(text "${AUTH}")" \
    -s "smtpServer.user=$(text "${SPRING_MAIL_USERNAME:-}")" \
    -s "smtpServer.password=$(text "${SPRING_MAIL_PASSWORD:-}")" \
    -s "smtpServer.starttls=$(text "${STARTTLS}")" \
    -s "smtpServer.ssl=$(text "${SSL}")"

echo "[keycloak-mail] Fertig."
