# This is an EDK2 Description file.
# This file describes how to build a package.
# cf. https://github.com/tianocore/tianocore.github.io/wiki/Build-Description-Files#the-dsc-file

# Defines the basic information of the package.
#@range_begin(defines)
[Defines]
  PLATFORM_NAME                  = ZakuroLoaderPkg
  PLATFORM_GUID                  = 6592191f-b809-429e-98fd-2f2f37db902f
  PLATFORM_VERSION               = 0.0
  DSC_SPECIFICATION              = 0x00010005
  OUTPUT_DIRECTORY               = Build/ZakuroLoader$(ARCH)
  SUPPORTED_ARCHITECTURES        = X64
  BUILD_TARGETS                  = DEBUG|RELEASE|NOOPT
#@range_end(defines)

# List of libraries this package depends on.
# This tells the build system where the library is located.
#@range_begin(library_classes)
[LibraryClasses]
  UefiApplicationEntryPoint|MdePkg/Library/UefiApplicationEntryPoint/UefiApplicationEntryPoint.inf
  UefiLib|MdePkg/Library/UefiLib/UefiLib.inf
#@range_end(library_classes)

  BaseLib|MdePkg/Library/BaseLib/BaseLib.inf
  BaseMemoryLib|MdePkg/Library/BaseMemoryLib/BaseMemoryLib.inf
  DebugLib|MdePkg/Library/BaseDebugLibNull/BaseDebugLibNull.inf
  DevicePathLib|MdePkg/Library/UefiDevicePathLib/UefiDevicePathLib.inf
  MemoryAllocationLib|MdePkg/Library/UefiMemoryAllocationLib/UefiMemoryAllocationLib.inf
  PcdLib|MdePkg/Library/BasePcdLibNull/BasePcdLibNull.inf
  PrintLib|MdePkg/Library/BasePrintLib/BasePrintLib.inf
  UefiBootServicesTableLib|MdePkg/Library/UefiBootServicesTableLib/UefiBootServicesTableLib.inf
  UefiRuntimeServicesTableLib|MdePkg/Library/UefiRuntimeServicesTableLib/UefiRuntimeServicesTableLib.inf
  RegisterFilterLib|MdePkg/Library/RegisterFilterLibNull/RegisterFilterLibNull.inf

# List of the components or modules to build for this package.
#@range_begin(components)
[Components]
  ZakuroLoaderPkg/Loader.inf
#@range_end(components)