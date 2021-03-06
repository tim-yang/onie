#-------------------------------------------------------------------------------
#
#
#-------------------------------------------------------------------------------
#
# This is a makefile fragment that defines the build of dmidecode
#

DMIDECODE_VERSION		= 2.12
DMIDECODE_TARBALL		= dmidecode-$(DMIDECODE_VERSION).tar.gz
DMIDECODE_TARBALL_URLS		+= $(ONIE_MIRROR) http://download.savannah.gnu.org/releases/dmidecode/
DMIDECODE_BUILD_DIR		= $(MBUILDDIR)/dmidecode
DMIDECODE_DIR			= $(DMIDECODE_BUILD_DIR)/dmidecode-$(DMIDECODE_VERSION)

DMIDECODE_SRCPATCHDIR		= $(PATCHDIR)/dmidecode
DMIDECODE_DOWNLOAD_STAMP	= $(DOWNLOADDIR)/dmidecode-download
DMIDECODE_SOURCE_STAMP		= $(STAMPDIR)/dmidecode-source
DMIDECODE_PATCH_STAMP		= $(STAMPDIR)/dmidecode-patch
DMIDECODE_BUILD_STAMP		= $(STAMPDIR)/dmidecode-build
DMIDECODE_INSTALL_STAMP		= $(STAMPDIR)/dmidecode-install
DMIDECODE_STAMP			= $(DMIDECODE_SOURCE_STAMP) \
				  $(DMIDECODE_PATCH_STAMP) \
				  $(DMIDECODE_BUILD_STAMP) \
				  $(DMIDECODE_INSTALL_STAMP)

DMIDECODE_PROGRAMS		= dmidecode

PHONY += dmidecode dmidecode-download dmidecode-source dmidecode-patch \
	dmidecode-build dmidecode-install dmidecode-clean dmidecode-download-clean

dmidecode: $(DMIDECODE_STAMP)

DOWNLOAD += $(DMIDECODE_DOWNLOAD_STAMP)
dmidecode-download: $(DMIDECODE_DOWNLOAD_STAMP)
$(DMIDECODE_DOWNLOAD_STAMP): $(PROJECT_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Getting upstream dmidecode ===="
	$(Q) $(SCRIPTDIR)/fetch-package $(DOWNLOADDIR) $(UPSTREAMDIR) \
		$(DMIDECODE_TARBALL) $(DMIDECODE_TARBALL_URLS)
	$(Q) touch $@

SOURCE += $(DMIDECODE_SOURCE_STAMP)
dmidecode-source: $(DMIDECODE_SOURCE_STAMP)
$(DMIDECODE_SOURCE_STAMP): $(TREE_STAMP) | $(DMIDECODE_DOWNLOAD_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Extracting upstream dmidecode ===="
	$(Q) $(SCRIPTDIR)/extract-package $(DMIDECODE_BUILD_DIR) $(DOWNLOADDIR)/$(DMIDECODE_TARBALL)
	$(Q) touch $@

dmidecode-patch: $(DMIDECODE_PATCH_STAMP)
$(DMIDECODE_PATCH_STAMP): $(DMIDECODE_SRCPATCHDIR)/* $(DMIDECODE_SOURCE_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Patching dmidecode ===="
	$(Q) $(SCRIPTDIR)/apply-patch-series $(DMIDECODE_SRCPATCHDIR)/series $(DMIDECODE_DIR)
	$(Q) touch $@

ifndef MAKE_CLEAN
DMIDECODE_NEW_FILES = $(shell test -d $(DMIDECODE_DIR) && test -f $(DMIDECODE_BUILD_STAMP) && \
	              find -L $(DMIDECODE_DIR) -newer $(DMIDECODE_BUILD_STAMP) -type f -print -quit)
endif

dmidecode-build: $(DMIDECODE_BUILD_STAMP)
$(DMIDECODE_BUILD_STAMP): $(DMIDECODE_PATCH_STAMP) $(DMIDECODE_NEW_FILES) | $(DEV_SYSROOT_INIT_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "====  Building dmidecode-$(DMIDECODE_VERSION) ===="
	$(Q) PATH='$(CROSSBIN):$(PATH)'	$(MAKE) -C $(DMIDECODE_DIR) \
		$(DMIDECODE_PROGRAMS) CROSS_COMPILE=$(CROSSPREFIX) \
			$(DMIDECODE_PROGRAMS)
	$(Q) touch $@

dmidecode-install: $(DMIDECODE_INSTALL_STAMP)
$(DMIDECODE_INSTALL_STAMP): $(SYSROOT_INIT_STAMP) $(DMIDECODE_BUILD_STAMP)
	$(Q) rm -f $@ && eval $(PROFILE_STAMP)
	$(Q) echo "==== Installing dmidecode programs in $(SYSROOTDIR) ===="
	$(Q) for file in $(DMIDECODE_PROGRAMS); do \
		cp -av $(DMIDECODE_DIR)/$$file $(SYSROOTDIR)/usr/bin ; \
	     done
	$(Q) touch $@

USERSPACE_CLEAN += dmidecode-clean
dmidecode-clean:
	$(Q) rm -rf $(DMIDECODE_BUILD_DIR)
	$(Q) rm -f $(DMIDECODE_STAMP)
	$(Q) echo "=== Finished making $@ for $(PLATFORM)"

DOWNLOAD_CLEAN += dmidecode-download-clean
dmidecode-download-clean:
	$(Q) rm -f $(DMIDECODE_DOWNLOAD_STAMP) $(DOWNLOADDIR)/$(DMIDECODE_TARBALL)

#-------------------------------------------------------------------------------
#
# Local Variables:
# mode: makefile-gmake
# End:
