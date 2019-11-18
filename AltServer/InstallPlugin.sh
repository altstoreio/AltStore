#!/bin/sh

#  InstallAltPlugin.sh
#  AltStore
#
#  Created by Riley Testut on 11/16/19.
#  Copyright © 2019 Riley Testut. All rights reserved.

mkdir -p /Library/Mail/Bundles
cp -r AltPlugin.mailbundle /Library/Mail/Bundles
defaults write "/Library/Preferences/com.apple.mail" EnableBundles 1
