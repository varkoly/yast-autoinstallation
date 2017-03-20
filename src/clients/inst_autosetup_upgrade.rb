# encoding: utf-8

# File:    clients/inst_autosetup.ycp
# Package: Auto-installation
# Summary: Setup and prepare system for auto-installation
# Authors: Anas Nashif <nashif@suse.de>
#          Uwe Gansert <ug@suse.de>
#
# $Id: inst_autosetup.ycp 61521 2010-03-29 09:10:07Z ug $
module Yast
  class InstAutosetupUpgradeClient < Client
    include Yast::Logger

    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "autoinst"

      Yast.import "AutoinstConfig"
      Yast.import "AutoInstall"
      Yast.import "Installation"
      Yast.import "Profile"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "AutoinstStorage"
      Yast.import "AutoinstScripts"
      Yast.import "AutoinstGeneral"
      Yast.import "AutoinstSoftware"
      Yast.import "Popup"
      Yast.import "Arch"
      Yast.import "Timezone"
      Yast.import "Keyboard"
      Yast.import "Call"
      Yast.import "ProductControl"
      Yast.import "Language"
      Yast.import "Console"

      Yast.include self, "autoinstall/ask.rb"

      @help_text = _(
        "<P>Please wait while the system is prepared for autoinstallation.</P>"
      )
      @progress_stages = [
        _("Configure General Settings "),
        _("Execute pre-install user scripts"),
        _("Set up language"),
        _("Registration"),
        _("Configure Software selections"),
        _("Configure Bootloader")
      ]

      @progress_descriptions = [
        _("Configuring general settings..."),
        _("Executing pre-install user scripts..."),
        _("Setting up language..."),
        _("Registering the system..."),
        _("Configuring Software selections..."),
        _("Configuring Bootloader...")
      ]

      Progress.New(
        _("Preparing System for Automated Installation"),
        "", # progress_title
        Builtins.size(@progress_stages), # progress bar length
        @progress_stages,
        @progress_descriptions,
        @help_text
      )


      return :abort if Popup.ConfirmAbort(:painless) if UI.PollInput == :abort
      Progress.NextStage


      # configure general settings





      return :abort if Popup.ConfirmAbort(:painless) if UI.PollInput == :abort

      Progress.NextStage

      # Pre-Scripts
      AutoinstScripts.Import(Ops.get_map(Profile.current, "scripts", {}))
      AutoinstScripts.Write("pre-scripts", false)

      # Reread Profile in case it was modified in pre-script
      # User has to create the new profile in a pre-defined
      # location for easy processing in pre-script.

      return :abort if readModified == :abort

      #
      # Partitioning and Storage
      #//////////////////////////////////////////////////////////////////////

      @modified = true
      begin
        askDialog
        # Pre-Scripts
        AutoinstScripts.Import(Ops.get_map(Profile.current, "scripts", {}))
        AutoinstScripts.Write("pre-scripts", false)
        @ret2 = readModified
        return :abort if @ret2 == :abort
        @modified = false if @ret2 == :not_found
      end while @modified == true

      # reimport scripts, for the case <ask> has changed them
      AutoinstScripts.Import(Ops.get_map(Profile.current, "scripts", {}))
      #
      # Set workflow variables
      #
      AutoinstGeneral.Import(Ops.get_map(Profile.current, "general", {}))
      Builtins.y2milestone(
        "general: %1",
        Ops.get_map(Profile.current, "general", {})
      )
      AutoinstGeneral.Write

      if Builtins.haskey(Profile.current, "add-on")
        Call.Function(
          "add-on_auto",
          ["Import", Ops.get_map(Profile.current, "add-on", {})]
        )
        Call.Function("add-on_auto", ["Write"])
      end

      @use_utf8 = true # utf8 is default

      @displayinfo = UI.GetDisplayInfo
      if !Ops.get_boolean(@displayinfo, "HasFullUtf8Support", true)
        @use_utf8 = false # fallback to ascii
      end


      #
      # Set it in the Language module.
      #
      Progress.NextStep
      Progress.Title(_("Configuring language..."))
      Language.Import(Ops.get_map(Profile.current, "language", {}))

      #
      # Set Console font
      #
      Installation.encoding = Console.SelectFont(Language.language)

      if Ops.get_boolean(@displayinfo, "HasFullUtf8Support", true)
        Installation.encoding = "UTF-8"
      end

      UI.SetLanguage(Language.language, Installation.encoding)
      WFM.SetLanguage(Language.language, "UTF-8")

      if Builtins.haskey(Profile.current, "timezone")
        Timezone.Import(Ops.get_map(Profile.current, "timezone", {}))
      end
      # bnc#891808: infer keyboard from language if needed
      if Profile.current.has_key?("keyboard")
        Keyboard.Import(Profile.current["keyboard"] || {}, :keyboard)
      elsif Profile.current.has_key?("language")
        Keyboard.Import(Profile.current["language"] || {}, :language)
      end


      # one can override the <confirm> option by the commandline parameter y2confirm
      @tmp = Convert.to_string(
        SCR.Read(path(".target.string"), "/proc/cmdline")
      )
      if @tmp != nil &&
          Builtins.contains(Builtins.splitstring(@tmp, " \n"), "y2confirm")
        AutoinstConfig.Confirm = true
        Builtins.y2milestone("y2confirm found and confirm turned on")
      end


      return :abort if Popup.ConfirmAbort(:painless) if UI.PollInput == :abort

      # moved here from autoinit for fate #301193
      # needs testing
      if Arch.s390 && AutoinstConfig.remoteProfile == true
        Builtins.y2milestone("arch=s390 and remote_profile=true")
        if Builtins.haskey(Profile.current, "dasd")
          Builtins.y2milestone("dasd found")
          if Call.Function("dasd_auto", ["Import", Ops.get_map(Profile.current, "dasd", {})])
            #Activate imported disk bnc#883747
            Call.Function("dasd_auto", [ "Write" ])
          end
        end
        if Builtins.haskey(Profile.current, "zfcp")
          Builtins.y2milestone("zfcp found")
          if Call.Function("zfcp_auto", ["Import", Ops.get_map(Profile.current, "zfcp", {})])
            #Activate imported disk bnc#883747
            Call.Function("zfcp_auto", [ "Write" ])
          end
        end
      end

      Progress.NextStage

      if !(Mode.autoupgrade && AutoinstConfig.ProfileInRootPart)
        # reread only if target system is not yet initialized (bnc#673033)
        log.error("FIXME : Missing storage call")
#       Storage.ReReadTargetMap
        if :abort == WFM.CallFunction("inst_update_partition_auto", [])
          return :abort
        end
      end

      # Registration
      # FIXME: There is a lot of duplicate code with inst_autosetup.

      return :abort if Popup.ConfirmAbort(:painless) if UI.PollInput == :abort
      Progress.NextStage

      general_section = Profile.current["general"] || {}
      if Profile.current["suse_register"]
        return :abort unless WFM.CallFunction(
          "scc_auto",
          ["Import", Profile.current["suse_register"]]
        )
        return :abort unless WFM.CallFunction(
          "scc_auto",
          ["Write"]
        )
	# failed relnotes download is not fatal, ignore ret code
	WFM.CallFunction("inst_download_release_notes")
      elsif general_section["semi-automatic"] &&
          general_section["semi-automatic"].include?("scc")

        Call.Function("inst_scc", ["enable_next" => true])
      end

      # Software

      return :abort if Popup.ConfirmAbort(:painless) if UI.PollInput == :abort

      Progress.NextStage

      # initialize package manager
      Yast.import "Packages"
      Yast.import "PackageCallbacks"
      Yast.import "Update"
      Yast.import "RootPart"
      Yast.import "ProductFeatures"
      Yast.import "Product"

      Packages.Init(true)

      # initialize target
      if true
        PackageCallbacks.SetConvertDBCallbacks

        Pkg.TargetInit(Installation.destdir, false)

        Update.GetProductName
      end

      # FATE #301990, Bugzilla #238488
      # Set initial update-related (packages/patches) values from control file
      Update.InitUpdate

      # some products are listed in media control file and at least one is compatible
      # with system just being updated
      @update_not_possible = false

      # FATE #301844
      Builtins.y2milestone(
        "Previous '%1', New '%2' RootPart",
        RootPart.previousRootPartition,
        RootPart.selectedRootPartition
      )
      if RootPart.previousRootPartition != RootPart.selectedRootPartition
        RootPart.previousRootPartition = RootPart.selectedRootPartition

        # check whether update is possible
        # reset deleteOldPackages and onlyUpdateInstalled in respect to the selected system
        Update.Reset
        if !Update.IsProductSupportedForUpgrade
          Builtins.y2milestone("Upgrade is not supported")
          @update_not_possible = true
        end
      end

      # this is new - override the default upgrade mode
      if Ops.get(Profile.current, ["upgrade", "only_installed_packages"]) != nil
        Update.onlyUpdateInstalled = Ops.get_boolean(
          Profile.current,
          ["upgrade", "only_installed_packages"],
          true
        )
      end

      # connect target with package manager
      if !Update.did_init1
        Update.did_init1 = true

        @restore = []
        @selected = Pkg.ResolvableProperties("", :product, "")
        Builtins.foreach(@selected) do |s|
          @restore = Builtins.add(@restore, Ops.get_string(s, "name", ""))
        end

        Pkg.PkgApplReset

        # bnc #300540
        # bnc #391785
        # Drops packages after PkgApplReset, not before (that would null that)
        Update.DropObsoletePackages

        Builtins.foreach(@restore) { |res| Pkg.ResolvableInstall(res, :product) }
        Update.SetDesktopPattern if !Update.onlyUpdateInstalled

        # make sure the packages needed for accessing the installation repository
        # are installed, e.g. "cifs-mount" for SMB or "nfs-client" for NFS repositories
        Packages.sourceAccessPackages.each do |package|
          Pkg::ResolvableInstall(package, :package)
        end

        Packages.SelectProduct

        if !Update.OnlyUpdateInstalled
          Packages.default_patterns.each do |pattern|
            result = Pkg.ResolvableInstall(pattern, :pattern)
            log.info "Pre-select pattern #{pattern}: #{result}"
          end

          # preselect the default product patterns (FATE#320199)
          # note: must be called *after* selecting the products
          require "packager/product_patterns"
          product_patterns = ProductPatterns.new
          log.info "Selecting the default product patterns: #{product_patterns.names}"
          product_patterns.select
        end


        # bnc #382208

        # bnc#582702 - do not select kernel on update, leave that on dependencies like 'zypper dup'
        # therefore commented line below out
        #          Packages::SelectKernelPackages ();

        # FATE #301990, Bugzilla #238488
        # Control the upgrade process better
        @update_sum = Pkg.PkgUpdateAll(GetUpdateConf())
        Builtins.y2milestone("Update summary: %1", @update_sum)
        Update.unknown_packages = Ops.get(@update_sum, :ProblemListSze, 0)

        @sys_patterns = Packages.ComputeSystemPatternList
        Builtins.foreach(@sys_patterns) do |pat|
          Pkg.ResolvableInstall(pat, :pattern)
        end
        # this is new, (de)select stuff from the profile
        @packages = Ops.get_list(Profile.current, ["software", "packages"], [])
        @patterns = Ops.get_list(Profile.current, ["software", "patterns"], [])
        @products = Ops.get_list(Profile.current, ["software", "products"], [])
        @remove_packages = Ops.get_list(
          Profile.current,
          ["software", "remove-packages"],
          []
        )
        @remove_patterns = Ops.get_list(
          Profile.current,
          ["software", "remove-patterns"],
          []
        )
        @remove_products = Ops.get_list(
          Profile.current,
          ["software", "remove-products"],
          []
        )
        # neutralize first, otherwise the change may have no effect
        Builtins.foreach(@remove_patterns) do |p|
          Pkg.ResolvableNeutral(p, :pattern, true)
        end
        Builtins.foreach(@remove_packages) do |p|
          Pkg.ResolvableNeutral(p, :package, true)
        end
        Builtins.foreach(@remove_products) do |p|
          Pkg.ResolvableNeutral(p, :product, true)
        end
        Builtins.foreach(@patterns) do |p|
          Pkg.ResolvableNeutral(p, :pattern, true)
        end
        Builtins.foreach(@packages) do |p|
          Pkg.ResolvableNeutral(p, :package, true)
        end
        Builtins.foreach(@products) do |p|
          Pkg.ResolvableNeutral(p, :product, true)
        end
        # now set the final status
        Builtins.foreach(@remove_patterns) do |p|
          Pkg.ResolvableRemove(p, :pattern)
        end
        Builtins.foreach(@remove_packages) do |p|
          Pkg.ResolvableRemove(p, :package)
        end
        Builtins.foreach(@remove_products) do |p|
          Pkg.ResolvableRemove(p, :product)
        end
        Builtins.foreach(@patterns) { |p| Pkg.ResolvableInstall(p, :pattern) }
        Builtins.foreach(@packages) { |p| Pkg.ResolvableInstall(p, :package) }
        Builtins.foreach(@products) { |p| Pkg.ResolvableInstall(p, :product) }
        # old stuff again here
        if Pkg.PkgSolve(!Update.onlyUpdateInstalled)
          Update.solve_errors = 0
        else
          Update.solve_errors = Pkg.PkgSolveErrors
          if Ops.get_boolean(
              Profile.current,
              ["upgrade", "stop_on_solver_conflict"],
              true
            )
            AutoinstConfig.Confirm = true
          end
        end
      end

      # Bootloader
      # FIXME: De-duplicate with inst_autosetup
      # Bootloader import / proposal is necessary to match changes done for manual
      # upgrade, when new configuration is created instead of reusing old one, which
      # cannot be converted from other bootloader configuration to GRUB2 format.
      # Without this code, YaST sticks with previously installed bootloader even if
      # it is not included in the new distro
      #
      # This fix was tested with AutoYaST profile as atached to bnc#885634 (*), as well as
      # its alternative without specifying bootloader settings, in VirtualBox with
      # single disk, updating patched SLES11-SP3 to SLES12 Beta10
      # https://bugzilla.novell.com/show_bug.cgi?id=885634#c3

      return :abort if UI.PollInput == :abort && Popup.ConfirmAbort(:painless)
      Progress.NextStage

      return :abort unless WFM.CallFunction(
        "bootloader_auto",
        ["Import", Ops.get_map(Profile.current, "bootloader", {})]
      )

      # SLES only, the only way to have kdump configured immediately after upgrade
      if Builtins.haskey(Profile.current, "kdump")
        Call.Function(
          "kdump_auto",
          ["Import", Ops.get_map(Profile.current, "kdump", {})]
        )
      end

      # Backup
      Builtins.y2internal("Backup: %1", Ops.get(Profile.current, "backup"))
      Installation.update_backup_modified = Ops.get_boolean(
        Profile.current,
        ["backup", "modified"],
        true
      )
      Builtins.y2internal(
        "Backup modified: %1",
        Installation.update_backup_modified
      )
      Installation.update_backup_sysconfig = Ops.get_boolean(
        Profile.current,
        ["backup", "sysconfig"],
        true
      )
      Installation.update_remove_old_backups = Ops.get_boolean(
        Profile.current,
        ["backup", "remove_old"],
        false
      )

      Progress.Finish

      @ret = ProductControl.RunFrom(
        Ops.add(ProductControl.CurrentStep, 1),
        true
      )
      return :finish if @ret == :next
      @ret
    end

    def readModified
      if Ops.greater_than(
          SCR.Read(path(".target.size"), AutoinstConfig.modified_profile),
          0
        )
        if !Profile.ReadXML(AutoinstConfig.modified_profile) ||
            Profile.current == {}
          Popup.Error(
            _(
              "Error while parsing the control file.\n" +
                "Check the log files for more details or fix the\n" +
                "control file and try again.\n"
            )
          )
          return :abort
        end
        cpcmd = Builtins.sformat(
          "mv %1 %2",
          "/tmp/profile/autoinst.xml",
          "/tmp/profile/pre-autoinst.xml"
        )
        Builtins.y2milestone("copy original profile: %1", cpcmd)
        SCR.Execute(path(".target.bash"), cpcmd)

        cpcmd = Builtins.sformat(
          "mv %1 %2",
          AutoinstConfig.modified_profile,
          "/tmp/profile/autoinst.xml"
        )
        Builtins.y2milestone("moving modified profile: %1", cpcmd)
        SCR.Execute(path(".target.bash"), cpcmd)
        return :found
      end
      :not_found
    end

    # FIXME FIXME FIXME copy-paste from update_proposal
    def GetUpdateConf
      # 'nil' values are skipped, in that case, ZYPP uses own default values
      ret = {}

      # not supported by libzypp anymore
      #      if (Update::deleteOldPackages != nil) {
      #          ret["delete_unmaintained"] = Update::deleteOldPackages;
      #      }

      if Update.silentlyDowngradePackages != nil
        Ops.set(ret, "silent_downgrades", Update.silentlyDowngradePackages)
      end

      Builtins.y2milestone("Using update configuration: %1", ret)

      deep_copy(ret)
    end
  end
end

Yast::InstAutosetupUpgradeClient.new.main
