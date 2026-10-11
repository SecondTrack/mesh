#!/bin/sh
# Gegenprobe iPod ↔ Android-Signal: baut tools/dev/signalinterop und lässt Interop.java (libsignal-
# protocol-java 2.8.1 aus dem Gradle-Cache der Android-App) dagegen laufen. Braucht JDK 17.
set -e
cd "$(dirname "$0")/../../.."
JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}
G=$HOME/.gradle/caches/modules-2/files-2.1
CP="$(ls $G/org.whispersystems/signal-protocol-java/2.8.1/*/signal-protocol-java-2.8.1.jar):$(ls $G/org.whispersystems/curve25519-java/0.5.0/*/curve25519-java-0.5.0.jar):$(ls $G/com.google.protobuf/protobuf-javalite/3.10.0/*/protobuf-javalite-3.10.0.jar)"
OUT=${TMPDIR:-/tmp}/mesh-interop; rm -rf "$OUT"; mkdir -p "$OUT"
sh tools/dev/build.sh signalinterop >/dev/null
"$JAVA_HOME/bin/javac" -cp "$CP" -d "$OUT" tools/dev/interop/Interop.java
"$JAVA_HOME/bin/java" -cp "$CP:$OUT" Interop "${OUT_TOOL:-/tmp/mesh-signalinterop}" "$OUT/ipod.plist"
