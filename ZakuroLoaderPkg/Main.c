#include <Guid/FileInfo.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/PrintLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Protocol/BlockIo.h>
#include <Protocol/BlockIo2.h>
#include <Protocol/DiskIo.h>
#include <Protocol/LoadedImage.h>
#include <Protocol/SimpleFileSystem.h>
#include <Uefi.h>

#include "frame_buffer.hpp"

/// Thin wrapper struct for UEFI memory map.
struct MemoryMap {
  UINTN buffer_size;
  VOID *buffer;
  UINTN map_size;
  /// Used to check the map is up-to-date.
  UINTN map_key;
  UINTN descriptor_size;
  UINT32 descriptor_version;
};

void Halt(void) {
  while (1) __asm__("hlt");
}

/// Get UEFI memory map.
EFI_STATUS GetMemoryMap(struct MemoryMap *map) {
  if (map->buffer == NULL) {
    return EFI_BUFFER_TOO_SMALL;
  }

  map->map_size = map->buffer_size;
  return gBS->GetMemoryMap(&map->map_size, (EFI_MEMORY_DESCRIPTOR *)map->buffer,
                           &map->map_key, &map->descriptor_size,
                           &map->descriptor_version);
}

/// Get printable string for UEFI memory type.
const CHAR16 *GetMemoryTypeUnicode(EFI_MEMORY_TYPE type) {
  switch (type) {
    case EfiReservedMemoryType:
      return L"EfiReservedMemoryType";
    case EfiLoaderCode:
      return L"EfiLoaderCode";
    case EfiLoaderData:
      return L"EfiLoaderData";
    case EfiBootServicesCode:
      return L"EfiBootServicesCode";
    case EfiBootServicesData:
      return L"EfiBootServicesData";
    case EfiRuntimeServicesCode:
      return L"EfiRuntimeServicesCode";
    case EfiRuntimeServicesData:
      return L"EfiRuntimeServicesData";
    case EfiConventionalMemory:
      return L"EfiConventionalMemory";
    case EfiUnusableMemory:
      return L"EfiUnusableMemory";
    case EfiACPIReclaimMemory:
      return L"EfiACPIReclaimMemory";
    case EfiACPIMemoryNVS:
      return L"EfiACPIMemoryNVS";
    case EfiMemoryMappedIO:
      return L"EfiMemoryMappedIO";
    case EfiMemoryMappedIOPortSpace:
      return L"EfiMemoryMappedIOPortSpace";
    case EfiPalCode:
      return L"EfiPalCode";
    case EfiPersistentMemory:
      return L"EfiPersistentMemory";
    case EfiMaxMemoryType:
      return L"EfiMaxMemoryType";
    default:
      return L"InvalidMemoryType";
  }
}

/// Write the given memory map to the file.
EFI_STATUS SaveMemoryMap(struct MemoryMap *map, EFI_FILE_PROTOCOL *file) {
  CHAR8 buf[256];
  UINTN len;

  CHAR8 *header =
      "Index, Type, Type(name), PhysicalStart, NumberOfPages, Attribute\n";
  len = AsciiStrLen(header);
  file->Write(file, &len, header);

  Print(L"map->buffer = 0x%08lx, map->map_size = 0x%08lx\n", map->buffer,
        map->map_size);

  EFI_PHYSICAL_ADDRESS iter;
  int i;
  for (iter = (EFI_PHYSICAL_ADDRESS)map->buffer, i = 0;
       iter < (EFI_PHYSICAL_ADDRESS)map->buffer + map->map_size;
       iter += map->descriptor_size, i++) {
    EFI_MEMORY_DESCRIPTOR *desc = (EFI_MEMORY_DESCRIPTOR *)iter;
    len = AsciiSPrint(buf, sizeof(buf), "%u, %x, %-ls, %08lx, %lx, %lx\n", i,
                      desc->Type, GetMemoryTypeUnicode(desc->Type),
                      desc->PhysicalStart, desc->NumberOfPages,
                      desc->Attribute & 0xffffflu);

    file->Write(file, &len, buf);
  }

  return EFI_SUCCESS;
}

EFI_STATUS OpenRootDir(EFI_HANDLE image_handle, EFI_FILE_PROTOCOL **root) {
  EFI_LOADED_IMAGE_PROTOCOL *loaded_image;
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs;

  gBS->OpenProtocol(image_handle, &gEfiLoadedImageProtocolGuid,
                    (VOID **)&loaded_image, image_handle, NULL,
                    EFI_OPEN_PROTOCOL_BY_HANDLE_PROTOCOL);
  gBS->OpenProtocol(loaded_image->DeviceHandle,
                    &gEfiSimpleFileSystemProtocolGuid, (VOID **)&fs,
                    image_handle, NULL, EFI_OPEN_PROTOCOL_BY_HANDLE_PROTOCOL);
  fs->OpenVolume(fs, root);

  return EFI_SUCCESS;
}

/// Open Graphics Output Protocol.
EFI_STATUS OpenGOP(EFI_HANDLE image_handle,
                   EFI_GRAPHICS_OUTPUT_PROTOCOL **gop) {
  UINTN num_gop_handles = 0;
  EFI_HANDLE *gop_handles = NULL;
  gBS->LocateHandleBuffer(ByProtocol, &gEfiGraphicsOutputProtocolGuid, NULL,
                          &num_gop_handles, &gop_handles);

  gBS->OpenProtocol(gop_handles[0], &gEfiGraphicsOutputProtocolGuid,
                    (VOID **)gop, image_handle, NULL,
                    EFI_OPEN_PROTOCOL_BY_HANDLE_PROTOCOL);

  FreePool(gop_handles);

  return EFI_SUCCESS;
}

const CHAR16 *GetPixelFormatUnicode(EFI_GRAPHICS_PIXEL_FORMAT fmt) {
  switch (fmt) {
    case PixelRedGreenBlueReserved8BitPerColor:
      return L"PixelRedGreenBlueReserved8BitPerColor";
    case PixelBlueGreenRedReserved8BitPerColor:
      return L"PixelBlueGreenRedReserved8BitPerColor";
    case PixelBitMask:
      return L"PixelBitMask";
    case PixelBltOnly:
      return L"PixelBltOnly";
    case PixelFormatMax:
      return L"PixelFormatMax";
    default:
      return L"InvalidPixelFormat";
  }
}

EFI_STATUS EFIAPI UefiMain(EFI_HANDLE image_handle,
                           EFI_SYSTEM_TABLE *system_table) {
  Print(L"Hello, world...!\n");

  // Save memory map
  CHAR8 memory_buf[4096 * 4];
  struct MemoryMap memmap = {
      .buffer_size = sizeof(memory_buf),
      .buffer = memory_buf,
      .map_size = 0,
      .map_key = 0,
      .descriptor_size = 0,
      .descriptor_version = 0,
  };
  GetMemoryMap(&memmap);

  EFI_FILE_PROTOCOL *root_dir;
  OpenRootDir(image_handle, &root_dir);

  EFI_FILE_PROTOCOL *memmap_file;
  root_dir->Open(
      root_dir, &memmap_file, L"\\memmap",
      EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE | EFI_FILE_MODE_CREATE, 0);

  SaveMemoryMap(&memmap, memmap_file);
  memmap_file->Close(memmap_file);

  Print(L"Saved a memory map to \\memmap.\n");

  // Open GOP
  EFI_GRAPHICS_OUTPUT_PROTOCOL *gop;
  OpenGOP(image_handle, &gop);
  Print(L"Resolution: %ux%u, Pixel Format: %s, %u pixels/line\n",
        gop->Mode->Info->HorizontalResolution,
        gop->Mode->Info->VerticalResolution,
        GetPixelFormatUnicode(gop->Mode->Info->PixelFormat),
        gop->Mode->Info->PixelsPerScanLine);
  Print(L"Frame Buffer: 0x%0lx - 0x%0lx, Size: %0lx bytes\n",
        gop->Mode->FrameBufferBase,
        gop->Mode->FrameBufferBase + gop->Mode->FrameBufferSize,
        gop->Mode->FrameBufferSize);

  // Load kernel image
  EFI_FILE_PROTOCOL *kernel_file;
  EFI_STATUS kern_setup_status = root_dir->Open(
      root_dir, &kernel_file, L"\\kernel.elf", EFI_FILE_MODE_READ, 0);
  if (EFI_ERROR(kern_setup_status)) {
    Print(L"failed to open file: %r\n", kern_setup_status);
    Halt();
  }

  UINTN file_info_size =
      sizeof(EFI_FILE_INFO) +
      sizeof(CHAR16) * 12;  // additional length for file name
  UINT8 file_info_buffer[file_info_size];
  kernel_file->GetInfo(kernel_file, &gEfiFileInfoGuid, &file_info_size,
                       file_info_buffer);

  EFI_FILE_INFO *file_info = (EFI_FILE_INFO *)file_info_buffer;
  UINTN kernel_file_size = file_info->FileSize;

  EFI_PHYSICAL_ADDRESS kernel_base_addr = 0x100000;
  kern_setup_status = gBS->AllocatePages(AllocateAddress, EfiLoaderData,
                                         (kernel_file_size + 0xfff) / 0x1000,
                                         &kernel_base_addr);
  if (EFI_ERROR(kern_setup_status)) {
    Print(L"failed to allocate pages: %r\n", kern_setup_status);
    Halt();
  }
  kern_setup_status = kernel_file->Read(kernel_file, &kernel_file_size,
                                        (VOID *)kernel_base_addr);
  if (EFI_ERROR(kern_setup_status)) {
    Print(L"failed to read file: %r\n", kern_setup_status);
    Halt();
  }
  Print(L"Kernel: 0x%0lx (%lx bytes)\n", kernel_base_addr, kernel_file_size);

#define ELF_OFFSET_TO_ENTRYPOINT 24
  UINT64 entry_addr = *(UINT64 *)(kernel_base_addr + ELF_OFFSET_TO_ENTRYPOINT);
  entry_addr -= 0x1000;  // TODO: must read program headers
  Print(L"Kernel entry point: 0x%lx\n", entry_addr);

  EFI_STATUS status;
  status = gBS->ExitBootServices(image_handle, memmap.map_key);
  if (EFI_ERROR(status)) {
    // ExitBootServices() may fail if the memory map has been changed.
    // Retry GetMemoryMap() and ExitBootServices() here.
    status = GetMemoryMap(&memmap);
    if (EFI_ERROR(status)) {
      Print(L"Failed to get memory map: %r\n", status);
      Halt();
    }
    status = gBS->ExitBootServices(image_handle, memmap.map_key);
    if (EFI_ERROR(status)) {
      Print(L"Could not exit boot service: %r\n", status);
      Halt();
    }
  }

  // prepare framebuffer config for argument of kernel entry point
  struct FrameBufferConfig config = {(UINT8 *)gop->Mode->FrameBufferBase,
                                     gop->Mode->Info->PixelsPerScanLine,
                                     gop->Mode->Info->HorizontalResolution,
                                     gop->Mode->Info->VerticalResolution, 0};
  switch (gop->Mode->Info->PixelFormat) {
    case PixelRedGreenBlueReserved8BitPerColor:
      config.pixel_format = kPixelRGBResv8BitPerColor;
      break;
    case PixelBlueGreenRedReserved8BitPerColor:
      config.pixel_format = kPixelBGRResv8BitPerColor;
      break;
    default:
      Print(L"Unimplemented pixel format: %d\n", gop->Mode->Info->PixelFormat);
      Halt();
  }

  typedef void EntryPointType(const struct FrameBufferConfig *);
  ((EntryPointType *)entry_addr)(&config);

  // unreachable

  Print(L"If you see this message, something went wrong!\n");
  Halt();

  return EFI_SUCCESS;
}
