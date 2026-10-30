#!/bin/bash
# ---------------------------------------------------------- #
# Bloqueo de telemetria y dominios (IA / estudio) en Pi-hole #
# Une: bloquear_telemetria.sh (solo "instalar")              #
#      + pihole_regex_dominios.sh                            #
# Para Pi-hole v6. Ejecutalo solo en el MASTER.              #
# Uso: sudo ./bloquear_todo.sh                               #
# ---------------------------------------------------------- #

# Modo Seguro
set -euo pipefail

# Colores
R='\e[1;31m'
G='\e[1;32m'
Y='\e[1;33m'
B='\e[1;34m'
N='\e[0m'

# Base de datos de Pi-hole donde se guardan los bloqueos
DB="/etc/pihole/gravity.db"

# Listas antitelemetria (Adlists)
LISTAS=(
  "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/multi.txt"
  "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt"
  "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/android-tracking.txt"
  "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/AmazonFireTV.txt"
)

# Dominios de telemetria (25) -> reglas regex
TELEMETRIA=(
  google-analytics.com doubleclick.net app-measurement.com crashlytics.com
  device-metrics-us.amazon.com fls-na.amazon.com unagi-na.amazon.com amazon-adsystem.com
  firebase-settings.crashlytics.com googlesyndication.com metrics.icloud.com api.smoot.apple.com
  iadsdk.apple.com lgappstv.com lgsmartad.com lgtvsdp.com
  lgtvcommon.com samsungacr.com samsungcloudsolution.net samsungelectronics.com
  samsungrm.net tracking.intl.miui.com data.mistat.intl.xiaomi.com ad.mi.com
  ad.xiaomi.com
)

# Dominios de IA / estudio (268) -> reglas regex
DOMINIOS_IA=(
  openai.com chatgpt.com gemini.google.com aistudio.google.com claude.ai
  anthropic.com perplexity.ai copilot.microsoft.com x.ai grok.com
  deepseek.com kimi.com qwen.ai mistral.ai meta.ai
  huggingface.co character.ai polybuzz.ai janitorai.com midjourney.com
  leonardo.ai ideogram.ai runwayml.com synthesia.io heygen.com
  elevenlabs.io suno.com suno.ai udio.com gamma.app
  cursor.com lovable.dev manus.im openrouter.ai duck.ai
  notebooklm.google.com consensus.app elicit.com phind.com you.com
  poe.com civitai.com stability.ai dreamstudio.ai stablediffusionweb.com
  craiyon.com artbreeder.com lexica.art tensor.art pixai.art
  seaart.ai civitaiarchive.com deepai.org nightcafe.studio fotor.com
  picsart.com canva.com remove.bg clipdrop.co phot.ai
  krea.ai magnific.ai fliki.ai invideo.io pictory.ai
  descript.com lumen5.com opus.pro vizard.ai vidyo.ai
  lalal.ai jasper.ai copy.ai rytr.me writesonic.com
  grammarly.com quillbot.com wordtune.com notion.so miro.com
  obsidian.md ollama.com anythingllm.com n8n.io magicschool.ai
  schoolai.com playlab.ai freepik.com bfl.ai firefly.adobe.com
  autodraw.com quickdraw.withgoogle.com tabnine.com sourcegraph.com blackbox.ai
  devin.ai bolt.new replit.com windsurf.com codeium.com
  continue.dev aider.chat cline.bot goose.ai crewai.com
  langchain.com llamaindex.ai haystack.deepset.ai pinecone.io weaviate.io
  qdrant.tech milvus.io chroma.com vectara.com mem0.ai
  autogpt.net agentops.ai e2b.dev composio.dev browserbase.com
  rivet.ai sora.com klingai.com pika.art lumalabs.ai
  synthesys.io d-id.com elai.io colossyan.com hourone.ai
  murf.ai resemble.ai play.ht lovo.ai speechify.com
  podcastle.ai cleanvoice.ai ai.azure.com ai.google deepmind.google
  research.google labs.google ai.meta.com ai21.com cohere.com
  together.ai replicate.com anyscale.com modal.com banana.dev
  fal.ai octoai.co fireworks.ai groq.com exa.ai
  tavily.com neeva.com andisearch.com komo.ai iask.ai
  scispace.com semanticscholar.org researchrabbit.ai connectedpapers.com litmaps.com
  inciteful.xyz openread.academy scite.ai paperpal.com typeset.io
  scholarcy.com summarizebot.com resoomer.com smmry.com tldrthis.com
  textcompactor.com tools4noobs.com paraphraser.io rewriteguru.com prepostseo.com
  duplichecker.com smallseotools.com seowriting.ai frase.io surferseo.com
  marketmuse.com clearscope.io contentharmony.com inkforall.com hypotenuse.ai
  copysmith.ai simplified.com describely.ai anyword.com copyscape.com
  originality.ai gptzero.me writer.com contentatscale.ai seo.ai
  neuroflash.com texta.ai ai-writer.com articleforge.com wordai.com
  spinrewriter.com chimpwriter.com aiarticlewriter.com contentbot.ai copymatic.ai
  zimmwriter.com textcortex.com hyperwriteai.com prowritingaid.com hemingwayapp.com
  slickwrite.com linguix.com ginger.com reverso.net deepl.com
  languagetool.org sapling.ai wordvice.ai trinka.ai paperrater.com
  virtualwritingtutor.com spellcheckplus.com ref-n-write.com academichelp.net wordvice.com
  enago.com editage.com scribbr.com chegg.com coursehero.com
  studocu.com quizlet.com brainly.com numerade.com mathway.com
  photomath.com wolframalpha.com symbolab.com socratic.org slader.com
  litanswers.org gradesaver.com sparknotes.com cliffsnotes.com shmoop.com
  litcharts.com supersummary.com bookrags.com enotes.com pinkmonkey.com
  novelguide.com antistudy.com freebooknotes.com bookwolf.com classicnotes.com
  studyworld.com bibliomania.com online-literature.com gutenberg.org librivox.org
  poets.org poetryfoundation.org bartleby.com
)

verificar_root() {
  if [ "$EUID" -ne 0 ]; then
    echo -e "$R Ejecuta este script con sudo.$N"
    exit 1
  fi
}

verificar_pihole() {
  if ! command -v pihole > /dev/null 2>&1 || [ ! -f "$DB" ]; then
    echo -e "$R Pi-hole v6 no esta instalado en este servidor ($DB no existe).$N"
    exit 1
  fi
}

# Ejecuta una instruccion SQL sobre gravity.db
ejecutar_sql() {
  pihole-FTL sqlite3 -ni "$DB" "$1"
}

# Mensaje: a donde van los bloqueos
mostrar_destino() {
  echo -e "$B ======================================================================$N"
  echo -e "$B  DESTINO DE LOS BLOQUEOS$N"
  echo -e "$B ======================================================================$N"
  echo -e "$Y  Base de datos:$N $DB"
  echo -e "$Y  Reglas regex ->$N tabla domainlist (type 3 = regex bloqueado)"
  echo -e "                 Web: Group Management > Domains"
  echo -e "$Y  Listas       ->$N tabla adlist"
  echo -e "                 Web: Group Management > Adlists"
  echo -e "$Y  Dominios de las listas ->$N tabla gravity (se llena con pihole -g)"
  echo -e "$Y  Aplican a:$N grupo Default = todos los clientes que usen este Pi-hole"
  echo -e "$Y  Backup:$N nebula-sync los copia al otro nodo (por eso se ejecuta solo en el master)"
  echo -e "$B ======================================================================$N"
}

# Listas antitelemetria -> tabla adlist (una sola transaccion, sin duplicar)
agregar_listas() {
  echo -e "$B Agregando listas antitelemetria...$N"
  local lista sql="BEGIN;"
  for lista in "${LISTAS[@]}"; do
    sql+="INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ('$lista', 1, 'telemetria');"
  done
  ejecutar_sql "${sql}COMMIT;"
}

# $1 = comentario, resto = dominios -> tabla domainlist, type 3 (regex bloqueado)
agregar_regex() {
  local comentario="$1" dominio regex sql="BEGIN;"
  shift
  echo -e "$B Agregando $# reglas regex ($comentario)...$N"
  for dominio in "$@"; do
    regex="^(.+\\.)??${dominio//./\\.}\$"
    sql+="INSERT OR IGNORE INTO domainlist (type, domain, enabled, comment) VALUES (3, '$regex', 1, '$comentario');"
  done
  ejecutar_sql "${sql}COMMIT;"
}

actualizar_gravity() {
  echo -e "$B Actualizando listas y reglas de Pi-hole (pihole -g)...$N"
  pihole -g
}

resumen() {
  local regex_nuevas=$(( $(ejecutar_sql "SELECT COUNT(*) FROM domainlist WHERE type=3;") - ANTES_REGEX ))
  local listas_nuevas=$(( $(ejecutar_sql "SELECT COUNT(*) FROM adlist;") - ANTES_LISTAS ))
  echo -e "$G Listo: $regex_nuevas reglas regex nuevas y $listas_nuevas listas nuevas.$N"
  echo -e "$G Guardado en: $DB (se puede repetir el script sin duplicar nada).$N"
  echo -e "$B Ver reglas :$N sudo pihole-FTL sqlite3 -header -column $DB \"SELECT id,domain,comment FROM domainlist WHERE type=3 LIMIT 10;\""
  echo -e "$B Ver listas :$N sudo pihole-FTL sqlite3 -header -column $DB \"SELECT id,address,enabled,number FROM adlist;\""
  echo -e "$B Probar     :$N pihole-FTL regex-test openai.com"
}

# Ejecucion
verificar_root
verificar_pihole
mostrar_destino
ANTES_REGEX=$(ejecutar_sql "SELECT COUNT(*) FROM domainlist WHERE type=3;")
ANTES_LISTAS=$(ejecutar_sql "SELECT COUNT(*) FROM adlist;")
agregar_listas
agregar_regex "telemetria" "${TELEMETRIA[@]}"
agregar_regex "dominios IA/estudio" "${DOMINIOS_IA[@]}"
actualizar_gravity
resumen
