flutter pub upgrade
yes | flutter doctor --android-licenses

# Set up Melos
export PATH="$PATH":"$HOME/.pub-cache/bin"

# Run tests
flutter drive -v --target=./test_driver/app.dart
cp report-ci.json ./output-files
