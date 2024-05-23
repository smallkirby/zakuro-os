/// Tag encoding for a DWARF abbreviation declaration.
pub const TagEncoding = enum(u64) {
    Reserved = 0x00,
    ArrayType = 0x01,
    ClassType = 0x02,
    EntryPoint = 0x03,
    EnumerationType = 0x04,
    FormalParameter = 0x05,
    ImportedDeclaration = 0x08,
    Label = 0x0A,
    LexicalBlock = 0x0B,
    Member = 0x0D,
    PointerType = 0x0F,
    ReferenceType = 0x10,
    CompileUnit = 0x11,
    StringType = 0x12,
    StructureType = 0x13,
    SubroutineType = 0x15,
    Typedef = 0x16,
    UnionType = 0x17,
    UnspecifiedParameters = 0x18,
    Variant = 0x19,
    CommonBlock = 0x1A,
    CommonInclusion = 0x1B,
    Inheritance = 0x1C,
    InlinedSubroutine = 0x1D,
    Module = 0x1E,
    PtrToMemberType = 0x1F,
    SetType = 0x20,
    SubrangeType = 0x21,
    WithStatement = 0x22,
    AccessDeclaration = 0x23,
    BaseType = 0x24,
    CatchBlock = 0x25,
    ConstType = 0x26,
    Constant = 0x27,
    Enumerator = 0x28,
    FileType = 0x29,
    Friend = 0x2A,
    Namelist = 0x2B,
    NameListItems = 0x2C,
    PackedType = 0x2D,
    Subprogram = 0x2E,
    TemplateTypeParameter = 0x2F,
    TemplateValueParameter = 0x30,
    ThrownType = 0x31,
    TryBlock = 0x32,
    VariantPart = 0x33,
    Variable = 0x34,
    VolatileType = 0x35,
    DwarfProcedure = 0x36,
    RestrictType = 0x37,
    InterfaceType = 0x38,
    Namespace = 0x39,
    ImportedModule = 0x3A,
    UnspecifiedType = 0x3B,
    PartialUnit = 0x3C,
    ImportedUnit = 0x3D,
    Condition = 0x3F,
    SharedType = 0x40,
    TypeUnit = 0x41,
    RvalueReferenceType = 0x42,
    TemplateAlias = 0x43,
    LoUser = 0x4080,
    HiUser = 0xFFFF,
};

/// Whether the DIE has children.
pub const ChildDetermination = enum(u8) {
    NoChildren = 0,
    HasChildren = 1,
};

/// Attribute name encoding for a DWARF abbreviation declaration.
/// This value is coupled with the `AttributeForm`.
pub const AttributeName = enum(u64) {
    Reserved = 0x00,
    Sibling = 0x01,
    Location = 0x02,
    Name = 0x03,
    Ordering = 0x09,
    ByteSize = 0x0B,
    BitOffset = 0x0C,
    BitSize = 0x0D,
    StmtList = 0x10,
    LowPc = 0x11,
    HighPc = 0x12,
    Language = 0x13,
    Discr = 0x15,
    DiscrValue = 0x16,
    Visibility = 0x17,
    Import = 0x18,
    StringLength = 0x19,
    CommonReference = 0x1A,
    CompDir = 0x1B,
    ConstValue = 0x1C,
    ContainingType = 0x1D,
    DefaultValue = 0x1E,
    Inline = 0x20,
    IsOptional = 0x21,
    LowerBound = 0x22,
    Producer = 0x25,
    Prototyped = 0x27,
    ReturnAddr = 0x2A,
    StartScope = 0x2C,
    BitStride = 0x2E,
    UpperBound = 0x2F,
    AbstractOrigin = 0x31,
    Accessibility = 0x32,
    AddressClass = 0x33,
    Artificial = 0x34,
    BaseTypes = 0x35,
    CallingConvention = 0x36,
    Count = 0x37,
    DataMemberLocation = 0x38,
    DeclColumn = 0x39,
    DeclFile = 0x3A,
    DeclLine = 0x3B,
    Declaration = 0x3C,
    DiscrList = 0x3D,
    Encoding = 0x3E,
    External = 0x3F,
    FrameBase = 0x40,
    Friend = 0x41,
    IdentifierCase = 0x42,
    MacroInfo = 0x43,
    NamelistItem = 0x44,
    Priority = 0x45,
    Segment = 0x46,
    Specification = 0x47,
    StaticLink = 0x48,
    Type = 0x49,
    UseLocation = 0x4A,
    VariableParameter = 0x4B,
    Virtuality = 0x4C,
    VtableElemLocation = 0x4D,
    Allocated = 0x4E,
    Associated = 0x4F,
    DataLocation = 0x50,
    ByteStride = 0x51,
    EntryPC = 0x52,
    UseUTF8 = 0x53,
    Extension = 0x54,
    Ranges = 0x55,
    Trampoline = 0x56,
    CallColumn = 0x57,
    CallFile = 0x58,
    CallLine = 0x59,
    Description = 0x5A,
    BinaryScale = 0x5B,
    DecimalScale = 0x5C,
    Small = 0x5D,
    DecimalSign = 0x5E,
    DigitCount = 0x5f,
    PictureString = 0x60,
    Mutable = 0x61,
    ThreadsScaled = 0x62,
    Explicit = 0x63,
    ObjectPointer = 0x64,
    Endianity = 0x65,
    Elemental = 0x66,
    Pure = 0x67,
    Recursive = 0x68,
    Signature = 0x69,
    MainSubprogram = 0x6A,
    DataBitOffset = 0x6B,
    ConstExpr = 0x6C,
    EnumClass = 0x6D,
    LinkageName = 0x6E,

    // DWARF5
    StringLengthBitSize = 0x6F,
    StringLengthByteSize = 0x70,
    Rank = 0x71,
    StrOffsetsBase = 0x72,
    AddrBase = 0x73,
    RnglistsBase = 0x74,
    DwoName = 0x76,
    Reference = 0x77,
    RvalueReference = 0x78,
    Macros = 0x79,
    CallAllCalls = 0x7A,
    CallAllSourceCalls = 0x7B,
    CallAllTailCalls = 0x7C,
    CallReturnPc = 0x7D,
    CallValue = 0x7E,
    CallOrigin = 0x7F,
    CallParameter = 0x80,
    CallPc = 0x81,
    CallTailCall = 0x82,
    CallTarget = 0x83,
    CallTargetClobbered = 0x84,
    CallDataLocation = 0x85,
    CallDataValue = 0x86,
    Noreturn = 0x87,
    Alignment = 0x88,
    ExportSymbols = 0x89,
    Deleted = 0x8A,
    Defaulted = 0x8B,
    LoclistsBase = 0x8C,

    LoUser = 0x2000,
    HiUser = 0x3FFF,

    pub fn from(v: u64) AttributeName {
        if (@intFromEnum(AttributeName.LoUser) <= v and v < @intFromEnum(AttributeName.HiUser)) {
            return AttributeName.LoUser;
        } else {
            return @enumFromInt(v);
        }
    }
};

/// Attribute encoding format for a DWARF abbreviation declaration.
pub const AttributeForm = enum(u64) {
    Reserved = 0x00,
    Addr = 0x01,
    Block2 = 0x03,
    Block4 = 0x04,
    Data2 = 0x05,
    Data4 = 0x06,
    Data8 = 0x07,
    String = 0x08,
    Block = 0x09,
    Block1 = 0x0A,
    Data1 = 0x0B,
    Flag = 0x0C,
    SData = 0x0D,
    Strp = 0x0E,
    UData = 0x0F,
    RefAddr = 0x10,
    Ref1 = 0x11,
    Ref2 = 0x12,
    Ref4 = 0x13,
    Ref8 = 0x14,
    RefUData = 0x15,
    Indirect = 0x16,
    SecOffset = 0x17,
    Exprloc = 0x18,
    FlagPresent = 0x19,
    RefSig8 = 0x20,
};