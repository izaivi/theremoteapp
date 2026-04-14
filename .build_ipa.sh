#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "==> flutter clean"
flutter clean

echo "==> flutter pub get"
flutter pub get

echo "==> pod install"
cd ios && pod install --repo-update && cd ..

echo "==> flutter build ipa --release (with Supabase + RevenueCat keys)"
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://spgsqadnqaeynthrquro.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNwZ3NxYWRucWFleW50aHJxdXJvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU2ODQ2MDEsImV4cCI6MjA5MTI2MDYwMX0.SMUadOWrw0xXsfZsxTTbzL_RCev7yAe067RrnPo6sd4 \
  --dart-define=RC_APPLE_KEY=appl_nizWIKpVHaGDcMQunpgdVfBaUfu

echo ""
echo "==> Done. IPA location:"
ls -la build/ios/ipa/*.ipa
echo ""
echo "==> Next: open Transporter.app and drag the .ipa to upload to TestFlight"
