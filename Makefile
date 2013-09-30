TARGET = :clang::4.3

include theos/makefiles/common.mk

TWEAK_NAME = SpotlightUI
SpotlightUI_FILES = Tweak.xm
SpotlightUI_LDFLAGS = -lspotlight
SpotlightUI_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

internal-after-install::
	install.exec "killall -9 backboardd searchd AppIndexer &>/dev/null"
