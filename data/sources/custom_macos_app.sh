#!/usr/bin/env bash
#
# Template payload for a custom macOS app — this is the script that will live
# inside YourApp.app/Contents/MacOS/ once wrapped by appify.
#
# Why bother: an app launched from the Dock or Finder inherits the *GUI*
# environment, not your login shell. Tools that shell out (SourceTree calling
# php, git hooks calling node, …) then pick up the system binary instead of the
# brew/asdf/nvm one and fail. Launching the real app from a shell script fixes
# the environment for good.
#
# Rename this file to your needs, edit the two sections below, then:
#
#   sh appify.sh custom_macos_app.sh "Custom SourceTree"
#   mv "Custom SourceTree.app" /Applications/

# --- 1. Environment -----------------------------------------------------------
# Load the same environment your terminal gets. Adapt to your shell/setup.
[ -f "${HOME}/.bash_profile" ] && . "${HOME}/.bash_profile";
[ -f "${HOME}/.zprofile" ] && . "${HOME}/.zprofile";

# Or pin things explicitly, e.g.:
# export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}";
# export PATH="$(brew --prefix php@8.3)/bin:${PATH}";

# --- 2. Payload ---------------------------------------------------------------
# What the app actually does. Here: launch the real application binary so it
# inherits everything set up above.
open /Applications/SourceTree.app/Contents/MacOS/SourceTree;
