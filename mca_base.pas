unit mca_base;

{$mode objfpc}{$H+}
{$inline on}

interface

uses
  Classes, SysUtils, Apiglio_Tree, blocks_definition, Zstream;

type
  TMCA_Stream=class
  private
    FStream:TMemoryStream;
    FMcaPoint:TPoint;
  public
    property Stream:TMemoryStream read FStream write FStream;
    property x:longint read FMcaPoint.x write FMcaPoint.x;
    property z:longint read FMcaPoint.y write FMcaPoint.y;
  public
    function LoadFromFile(filename:string):boolean;
    function ChunkAvailable(chunk_index:word):boolean;
    procedure SaveToFile;
  public
    constructor Create;
    destructor Destroy;override;
  end;

  TChunk_Stream=class
  private
    FStream:TMemoryStream;
    FChunkPoint:TPoint;
    FChunkId:word;
  public
    property Stream:TMemoryStream read FStream write FStream;
    property xPos:longint read FChunkPoint.x write FChunkPoint.x;
    property zPos:longint read FChunkPoint.y write FChunkPoint.y;
  public
    function LoadFromMCA(chunk_index:word;mca:TMCA_Stream):boolean;
    procedure Decode(tree:TATree);
    procedure SaveToFile;
  public
    constructor Create;
    destructor Destroy;override;
  end;

  TChunk_Block=class
  private
    FStream:TMemoryStream;
    FBiomes:TMemoryStream;
    FMB,FMBN,FOF,FOFW,FWS,FWSW:array[0..256]of word;//高度图，其中第256位为0表示高度图无效
    xPos,zPos:longint;
  protected
    function GetHeightMap_MB(block_index:byte):word;
    function GetHeightMap_MBN(block_index:byte):word;
    function GetHeightMap_OF(block_index:byte):word;
    function GetHeightMap_OFW(block_index:byte):word;
    function GetHeightMap_WS(block_index:byte):word;
    function GetHeightMap_WSW(block_index:byte):word;

    procedure SetHeightMap_MB(block_index:byte;value:word);
    procedure SetHeightMap_MBN(block_index:byte;value:word);
    procedure SetHeightMap_OF(block_index:byte;value:word);
    procedure SetHeightMap_OFW(block_index:byte;value:word);
    procedure SetHeightMap_WS(block_index:byte;value:word);
    procedure SetHeightMap_WSW(block_index:byte;value:word);

  public
    property Stream:TMemoryStream read FStream write FStream;
    property Biomes:TMemoryStream read FBiomes write FBiomes;
    property motion_blocking[block_index:byte]:word read GetHeightMap_MB write SetHeightMap_MB;
    property motion_blocking_on_leaves[block_index:byte]:word read GetHeightMap_MBN write SetHeightMap_MBN;
    property ocean_floor[block_index:byte]:word read GetHeightMap_OF write SetHeightMap_OF;
    property ocean_floor_wg[block_index:byte]:word read GetHeightMap_OFW write SetHeightMap_OFW;
    property world_surface[block_index:byte]:word read GetHeightMap_WS write SetHeightMap_WS;
    property world_surface_wg[block_index:byte]:word read GetHeightMap_WSW write SetHeightMap_WSW;

    property MB_Enable:word read FMB[256] write FMB[256];
    property MBN_Enable:word read FMBN[256] write FMBN[256];
    property OF_Enable:word read FOF[256] write FOF[256];
    property OFW_Enable:word read FOFW[256] write FOFW[256];
    property WS_Enable:word read FWS[256] write FWS[256];
    property WSW_Enable:word read FWSW[256] write FWSW[256];

    property x:longint read xPos write xPos;
    property z:longint read zPos write zPos;

  public
    function OnlyOneChunk(tree:TATree):boolean;inline;
    //检验tree里是否只有1个chunk
    function HasPalette(tree:TATree):boolean;inline;
    //用于判断是否是扁平化之后的版本，仅接受唯一（第1个）chunk
    function HasHeightMaps(tree:TATree):boolean;inline;
    //用于判断是否是有多个高度图的版本，仅接受唯一（第1个）chunk



  protected//这一部分不同版本做法不同，但全部用LoadFromTree来调用，外部不可用
    procedure ExtractChunkPos(tree:TATree);inline;//仅接受唯一（第1个）chunk
    function ExtractBiomes(tree:TATree):boolean;//仅接受唯一（第1个）chunk
    function ExtractBlocks_164(tree:TATree):boolean;//仅接受唯一（第1个）chunk
    function ExtractBlocks_1_13(tree:TATree):boolean;//仅接受唯一（第1个）chunk
    function ExtractHeightMap_164(tree:TATree):boolean;//仅接受唯一（第1个）chunk
    function ExtractHeightMap_1_13(tree:TATree):boolean;//仅接受唯一（第1个）chunk

  public
    function LoadFromTree(tree:TATree):boolean;
    procedure SaveToFile(filename:string);
    procedure SaveByteToFile(filename:string);
    procedure SaveHeightMapToFile(filename:string);


  public
    constructor Create;
    destructor Destroy;override;
  end;//改成四个字节为一组，add blk dat nul（与TBitMap的BGRa格式统一）


implementation

{ TMCA_Stream }

function MCAFileToXZ(filename:string):TPoint;
var tmp1,tmp2:string;
    po:integer;
begin
  tmp2:=ExtractFilename(filename);
  if (pos('r.',tmp2)=1) and (pos('.mca',tmp2)=length(tmp2)-3) then
    begin
      tmp1:=tmp2;
      delete(tmp1,1,2);
      delete(tmp1,length(tmp1)-3,4);
      if pos('.',tmp1)<=0 then raise Exception.Create('') else begin
        tmp2:=tmp1;
        po:=pos('.',tmp1);
        try
          delete(tmp1,po,999);
          delete(tmp2,1,po);
          result.x:=StrToInt(tmp1);
          result.y:=StrToInt(tmp2);
        except
          raise Exception.Create('')
        end;
      end;
    end
  else raise Exception.Create('');
end;

function TMCA_Stream.LoadFromFile(filename:string):boolean;
var Pos:TPoint;
begin
  result:=true;
  try
    Pos:=McaFileToXZ(filename);
    Self.FStream.LoadFromFile(filename);
    Self.FMcaPoint:=Pos;
  except
    result:=false;
  end;
end;
procedure TMCA_Stream.SaveToFile;
begin
  FStream.SaveToFile('TMCA_Stream['+IntToStr(Self.x)+','+IntToStr(Self.z)+'].tmp');
end;

function TMCA_Stream.ChunkAvailable(chunk_index:word):boolean;
begin
  result:=false;
  if FStream.Size<8192 then exit;
  FStream.Position:=chunk_index*4+3;
  if FStream.Readbyte=0 then result:=false
  else result:=true;
end;

constructor TMCA_Stream.Create;
begin
  inherited Create;
  FStream:=TMemoryStream.Create;
end;

destructor TMCA_Stream.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;


{ TChunk_Stream }

function TChunk_Stream.LoadFromMCA(chunk_index:word;mca:TMCA_Stream):boolean;
var offset,size:dword;
    block:byte;
begin
  if not assigned(mca) then raise Exception.Create('MCA文件流未指派。');

  mca.Stream.Position:=chunk_index*4;
  offset:=mca.Stream.Readbyte shl 16;
  offset:=offset+mca.Stream.Readbyte shl 8;
  offset:=offset+mca.Stream.Readbyte;
  block:=mca.Stream.Readbyte;
  mca.Stream.Position:=offset*4096;
  size:=mca.Stream.ReadByte shl 24;
  size:=size+mca.Stream.ReadByte shl 16;
  size:=size+mca.Stream.ReadByte shl 8;
  size:=size+mca.Stream.ReadByte;
  if size>block*4096-4 then size:=block*4096-4;//20210117 针对迅雷错误版本的mca[0,-1]chunk[164]额外设置，本不必要，未必安全

  FStream.SetSize(size);
  FStream.position:=0;
  mca.Stream.Position:=offset*4096+5;
  FStream.CopyFrom(mca.Stream,size-1);

  FChunkId:=chunk_Index;
  FChunkPoint.x:=FChunkId mod 32 + mca.x*32;
  FChunkPoint.y:=FChunkId div 32 + mca.z*32;
  result:=true;
end;


procedure TChunk_Stream.Decode(tree:TATree);
var
  ds:TDecompressionStream;
  tmpStream:TMemoryStream;
  adapter:TNBT_Adapter;
  adapter_str:PChar;
  RawNbtType,ListType:byte;
  NameLen,DataLen:word;
  ArrayLen:dword;
  StrArray:array[0..65535]of char;
  iArr:word;
  WideName:widestring;
begin
  if FStream.Size=0 then begin raise Exception.Create('ChunkStream没有内容，未进行解码。');exit end;
  FStream.Position:=0;
  ds:=TDecompressionStream.Create(FStream);
  ds.position:=0;
  while true do
    BEGIN
      if (tree.Current.NbtType=NBT_List)and(tree.Current.ListId=0) then
        begin
          tree.CurrentOut;
          if tree.Current.NbtType=NBT_list then begin
            tree.Current.ListId:=tree.Current.ListId - 1;
            RawNbtType:=tree.Current.ListType;
          end;
          continue;
        end;
      if tree.Current.NbtType<>NBT_List then
        begin
          ds.read(RawNbtType,1);
        end;
      WideName:='';
      if NBT(RawNbtType)=NBT_End then
        begin
          //
        end
      else if tree.Current.NbtType=NBT_List then
        begin
          WideName:='List_'+NBT_Typist(NBT(RawNbtType))+'['+IntToStr(tree.Current.ListId)+']';
        end
      else
        begin
          WideName:='';
          ds.Readbuffer(NameLen,2);
          NameLen:=SwapEndian(NameLen);
          if NameLen>0 then begin
            ds.read(StrArray[0],NameLen);
            for iArr:=0 to NameLen-1 do WideName:=WideName+StrArray[iArr];
          end;
        end;
      case NBT(RawNbtType) of
        NBT_End:
          begin
            if tree.Current=tree.root then break;
            tree.CurrentOut;//跳的是Compound的这一级
            if tree.Current.NbtType=NBT_List then
              begin
                dec(tree.Current.ListId);
                RawNbtType:=tree.Current.ListType;
              end;
          end;
        NBT_Byte:
          begin
            ds.readbuffer(adapter.vByte,1);
            tree.AddByte(WideName,adapter.vByte);
          end;
        NBT_Short:
          begin
            ds.readbuffer(adapter.vShort,2);
            tree.AddShort(WideName,adapter.vShort);
          end;
        NBT_Int:
          begin
            ds.readbuffer(adapter.vInt,4);
            tree.AddInt(WideName,adapter.vInt);
          end;
        NBT_Long:
          begin
            ds.readbuffer(adapter.vLong,8);
            tree.AddLong(WideName,adapter.vLong);
          end;
        NBT_Float:
          begin
            ds.readbuffer(adapter.vFloat,4);
            tree.AddFloat(WideName,adapter.vFloat);
          end;
        NBT_Double:
          begin
            ds.readbuffer(adapter.vDouble,8);
            tree.AddDouble(WideName,adapter.vDouble);
          end;
        NBT_ByteArray:
          begin
            ds.readbuffer(ArrayLen,4);
            ArrayLen:=SwapEndian(ArrayLen);
            ds.readbuffer(tree.AddByteArray(WideName,ArrayLen)^,ArrayLen*1);
          end;
        NBT_String:
          begin
            ds.readbuffer(DataLen,2);
            DataLen:=SwapEndian(DataLen);
            ds.readbuffer(tree.AddString(WideName,DataLen)^,DataLen);
          end;
        NBT_List:
          begin
            ds.read(ListType,1);
            ArrayLen:=ds.readDWord;
            ArrayLen:=SwapEndian(ArrayLen);
            tree.AddUnit(WideName,nil,NBT(RawNbtType));
            tree.CurrentInto(WideName);
            tree.Current.ListType:=ListType;
            if NBT(ListType)=NBT_Compound then
              tree.Current.ListId:=ArrayLen//复合类型的ListId计算在Tag_End中，本次不计算
            else
              tree.Current.ListId:=ArrayLen+1;//非复合类型的ListId计算在末尾，计算本次
            RawNbtType:=ListType;
          end;
        NBT_Compound:
          begin
            if (WideName='') and (tree.Current=tree.root) then WideName:='chunk['+IntToStr(FChunkId)+']';
            tree.AddUnit(WideName,nil,NBT(RawNbtType));
            tree.CurrentInto(WideName);
          end;
        NBT_IntArray:
          begin
            ds.readbuffer(ArrayLen,4);
            ArrayLen:=SwapEndian(ArrayLen);
            ds.readbuffer(tree.AddIntArray(WideName,ArrayLen)^,ArrayLen*4);
          end;
        NBT_LongArray:
          begin
            ds.readbuffer(ArrayLen,4);
            ArrayLen:=SwapEndian(ArrayLen);
            ds.readbuffer(tree.AddLongArray(WideName,ArrayLen)^,ArrayLen*8);

          end;
        else ;
      end;
      if (tree.Current.NbtType=NBT_List)and(NBT(tree.Current.ListType)<>NBT_Compound) then
        begin
          tree.Current.ListId:=tree.Current.ListId - 1;
        end;
    END;

  ds.Free;
end;

procedure TChunk_Stream.SaveToFile;
begin
  FStream.SaveToFile('TChunk_Stream['+IntToStr(Self.xPos)+','+IntToStr(Self.zPos)+'].tmp');
end;

constructor TChunk_Stream.Create;
begin
  inherited Create;
  FStream:=TMemoryStream.Create;
end;

destructor TChunk_Stream.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;


{ TChunk_Block }

function TChunk_Block.GetHeightMap_MB(block_index:byte):word;
begin
  result:=FMB[block_index];
end;
function TChunk_Block.GetHeightMap_MBN(block_index:byte):word;
begin
  result:=FMBN[block_index];
end;
function TChunk_Block.GetHeightMap_OF(block_index:byte):word;
begin
  result:=FOF[block_index];
end;
function TChunk_Block.GetHeightMap_OFW(block_index:byte):word;
begin
  result:=FOFW[block_index];
end;
function TChunk_Block.GetHeightMap_WS(block_index:byte):word;
begin
  result:=FWS[block_index];
end;
function TChunk_Block.GetHeightMap_WSW(block_index:byte):word;
begin
  result:=FWSW[block_index];
end;

procedure TChunk_Block.SetHeightMap_MB(block_index:byte;value:word);
begin
  FMB[block_index]:=value;
end;
procedure TChunk_Block.SetHeightMap_MBN(block_index:byte;value:word);
begin
  FMBN[block_index]:=value;
end;
procedure TChunk_Block.SetHeightMap_OF(block_index:byte;value:word);
begin
  FOF[block_index]:=value;
end;
procedure TChunk_Block.SetHeightMap_OFW(block_index:byte;value:word);
begin
  FOFW[block_index]:=value;
end;
procedure TChunk_Block.SetHeightMap_WS(block_index:byte;value:word);
begin
  FWS[block_index]:=value;
end;
procedure TChunk_Block.SetHeightMap_WSW(block_index:byte;value:word);
begin
  FWSW[block_index]:=value;
end;

{ TChunk_Block }

function TChunk_Block.OnlyOneChunk(tree:TATree):boolean;inline;
begin
  if tree.root.Achild.count<>1 then result:=false else result:=true;
end;
procedure TChunk_Block.ExtractChunkPos(tree:TATree);
begin
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  tree.CurrentInto('Level');
  tree.CurrentInto('xPos');
  Self.xPos:=tree.Current.RInt;
  tree.CurrentOut;
  tree.CurrentInto('zPos');
  Self.zPos:=tree.Current.RInt;
  tree.CurrentOut;
end;
function TChunk_Block.HasPalette(tree:TATree):boolean;
var tmp:TAListUnit;
    has_palette,has_blocks:boolean;
begin
  result:=false;
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  tree.CurrentInto('Level');
  tree.CurrentInto('Sections');
  tmp:=tree.Current.Achild.first;
  while tmp<>nil do
    begin
      tree.CurrentInto(tmp.obj as TATreeUnit);
      has_palette:=tree.CurrentInto('Palette');
      if has_palette then begin result:=true;exit end else tree.CurrentOut;
      has_blocks:=tree.CurrentInto('Blocks');
      if has_blocks then exit else tree.CurrentOut;
      tmp:=tmp.next;
    end;
end;
function TChunk_Block.HasHeightMaps(tree:TATree):boolean;
begin
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  tree.CurrentInto('Level');
  if tree.CurrentInto('Heightmaps') then result:=true
  else result:=false;
end;


function TChunk_Block.ExtractBlocks_164(tree:TATree):boolean;
var tmp:TAListUnit;
    SectionsId:byte;
    pi:dword;
    btmp,bl,bh:byte;
begin
  result:=false;
  FStream.SetSize(16*16*256*4);
  FStream.position:=0;

  while FStream.position<FStream.Size do
    begin
      FStream.WriteQWord($ff000000ff000000);
    end;
  {
  for bl:=0 to 255 do
    begin
    pi:=bl shl 24;
    for bh:=0 to 127 do
      begin
        FStream.WriteDWord(pi);
      end;
    end;
  }//颜色压缩所以四个波段并非独立
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  if not tree.CurrentInto('Level') then exit;
  if not tree.CurrentInto('Sections') then exit;
  tmp:=tree.Current.AChild.first;
  while tmp<>nil do
    begin
      tree.CurrentInto(tmp.obj as TATreeUnit);
      tree.CurrentInto('Y');
      SectionsId:=tree.Current.AByte;
      tree.CurrentOut;

      tree.CurrentInto('Blocks');
      FStream.position:=SectionsId*4096*4+1;//add blk dat nul
      for pi:=0 to 16*16*16-1 do
        begin
          btmp:=tree.Current.AByteArray[pi];
          FStream.WriteByte(btmp);
          FStream.Seek(3,soFromCurrent);
        end;
      tree.CurrentOut;
      if tree.CurrentInto('Add') then BEGIN
      FStream.position:=SectionsId*4096*4+0;
      for pi:=0 to 16*16*8-1 do
        begin
          btmp:=tree.Current.AByteArray[pi];
          bh:=btmp div 16;
          bl:=btmp mod 16;
          FStream.WriteByte(bl);
          FStream.Seek(3,soFromCurrent);
          FStream.WriteByte(bh);
          FStream.Seek(3,soFromCurrent);
        end;
      tree.CurrentOut;
      END ELSE BEGIN
      FStream.position:=SectionsId*4096*4+0;
      for pi:=0 to 16*16*8-1 do
        begin
          btmp:=0;
          FStream.WriteByte(btmp);
          FStream.Seek(3,soFromCurrent);
          FStream.WriteByte(btmp);
          FStream.Seek(3,soFromCurrent);
        end;
      END;
      tree.CurrentInto('Data');
      FStream.position:=SectionsId*4096*4+2;
      for pi:=0 to 16*16*8-1 do
        begin
          btmp:=tree.Current.AByteArray[pi];
          bh:=btmp div 16;
          bl:=btmp mod 16;
          FStream.WriteByte(bl);
          FStream.Seek(3,soFromCurrent);
          FStream.WriteByte(bh);
          FStream.Seek(3,soFromCurrent);
        end;
      tree.CurrentOut;
      tree.CurrentOut;
      tmp:=tmp.next;
    end;
  result:=true;
end;



function TChunk_Block.ExtractBlocks_1_13(tree:TATree):boolean;
var tmp,palette_unit:TAListUnit;
    SectionsId:byte;
    palette_count,pi:dword;
    block_defs:array[0..4095]of integer;
    band,buffer,bindex:int64;
    btimes,bsh:byte;
    mem:pbyte;

    function ceil(inp:double):int64;
    begin
      if inp=trunc(inp) then result:=trunc(inp)
      else result:=trunc(inp)+1;
    end;

begin
  result:=false;
  FStream.SetSize(16*16*256*4);
  FStream.position:=0;

  while FStream.position<FStream.Size do
    begin
      FStream.WriteQWord($0000000000000000);
    end;
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  if not tree.CurrentInto('Level') then exit;
  if not tree.CurrentInto('Sections') then exit;
  tmp:=tree.Current.AChild.first;
  while tmp<>nil do
    begin
      tree.CurrentInto(tmp.obj as TATreeUnit);
      tree.CurrentInto('Y');
      SectionsId:=tree.Current.AByte;
      tree.CurrentOut;

      if tree.CurrentInto('Palette') then
        begin
          palette_unit:=tree.Current.Achild.first;
          pi:=0;
          while palette_unit<>nil do
            begin
              tree.CurrentInto(palette_unit.obj as TATreeUnit);
              tree.CurrentInto('Name');
              block_defs[pi]:=defaultBlocks.AddBlockId(tree.Current.AString);
              inc(pi);
              palette_unit:=palette_unit.next;
            end;
          palette_count:=pi;
        end
      else
        begin
          tmp:=tmp.next;
          continue;//没有方块索引的子区块直接退出
        end;

      tree.CurrentOut;//Palette[i]
      tree.CurrentOut;//Palette
      tree.CurrentOut;//Sections

      tree.CurrentInto('BlockStates');

      if palette_count<=16 then begin
        band:=$000000000000000F;btimes:=15;bsh:=4;
      end else if palette_count<=32 then begin
        band:=$000000000000001F;btimes:=11;bsh:=5;
      end else if palette_count<=64 then begin
        band:=$000000000000003F;btimes:=9;bsh:=6;
      end else if palette_count<=128 then begin
        band:=$000000000000007F;btimes:=8;bsh:=7;
      end else if palette_count<=256 then begin
        band:=$00000000000000FF;btimes:=7;bsh:=8;
      end else if palette_count<=512 then begin
        band:=$00000000000001FF;btimes:=6;bsh:=9;
      end else if palette_count<=1024 then begin
        band:=$00000000000003FF;btimes:=5;bsh:=10;
      end else if palette_count<=2048 then begin
        band:=$00000000000007FF;btimes:=4;bsh:=11;
      end else begin
        band:=$0000000000000FFF;btimes:=4;bsh:=12;
      end;

      if tree.Current.size = ceil(4096/(btimes+1)) then begin //1.16
        FStream.position:=SectionsId*4096*4+0;
        for pi:=0 to tree.Current.size do
          begin
            buffer:=tree.Current.ALongArray[pi];
            buffer:=SwapEndian(buffer);
            for bindex:=0 to btimes do
              begin
                FStream.WriteDWord(block_defs[buffer and band]);
                buffer:=buffer shr bsh;
              end;
          end;
      end else if tree.Current.size = bsh*64 then begin //1.13


        getmem(mem,36*8+1);
        for pi:=0 to bsh*64-1 do
          (pint64(mem)+(bsh*64-1-pi))^:=tree.Current.RLongArray[pi];
        for pi:=0 to 4095 do
          begin
            buffer:=pword(mem+((4095-pi)*9 div 8))^;
            buffer:=SwapEndian(buffer);
            buffer:=buffer shr ((((4095-pi)+2)*bsh div 8)*8 - (4095-pi)*bsh-bsh);
            FStream.WriteDWord(block_defs[buffer and band]);
          end;
        freemem(mem,36*8+1);

      end else begin assert(false,'BlockStates位数不正确');exit end;

      tmp:=tmp.next;
    end;
  result:=true;
end;

function TChunk_Block.ExtractBiomes(tree:TATree):boolean;
var pi:word;
    btmp,floor:byte;
begin
  result:=false;
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  if not tree.CurrentInto('Level') then exit;
  if not tree.CurrentInto('Biomes') then exit;
  case tree.Current.size of
    256:
      begin
        Self.FBiomes.Position:=0;
        Self.FBiomes.SetSize(16*16*256*4);
        while Self.FBiomes.Position<Self.FBiomes.Size do
          begin
            Self.FBiomes.WriteDWord(tree.Current.AByteArray[(Self.FBiomes.Position div 4) mod 256]);
          end;
      end;
    1024:
      begin
        //立体的还没写
      end;
    else begin assert(false,'Biomes长度不是256或1024');exit end;
  end;
  result:=true;
end;


function TChunk_Block.ExtractHeightMap_164(tree:TATree):boolean;
var pi:word;
    btmp:byte;
begin
  FWS[256]:=0;
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  if not tree.CurrentInto('Level') then exit;
  tree.CurrentInto('HeightMap');
  for pi:=0 to 255 do
    begin
      btmp:=tree.Current.RIntArray[pi];
      FWS[pi]:=btmp;
    end;
  FWS[256]:=255;
  result:=true;
end;

procedure MonoHeightMap_1_16(node:TATreeUnit;HeightMap:pword);
var pi,pos:word;
    bindex:byte;
    buffer:int64;
begin
  pos:=0;
  for pi:=0 to 36 do
    begin
      buffer:=node.RLongArray[pi];
      for bindex:=0 to 6 do
        begin
          if pos<256 then (HeightMap+pos)^:=buffer and $00000000000001ff;//不太高明，能用就行。
          buffer:=buffer shr 9;
          inc(pos);
        end;
    end;
  (HeightMap+256)^:=255;
end;
procedure MonoHeightMap_1_13(node:TATreeUnit;HeightMap:pword);
var buffer,pi:word;
    tmp:pbyte;
begin

  getmem(tmp,36*8);
  for pi:=0 to 35 do
    (pint64(tmp)+(35-pi))^:=node.ALongArray[pi];
  for pi:=0 to 255 do
    begin
      buffer:=pword(tmp+(pi*9 div 8))^;
      buffer:=SwapEndian(buffer);
      buffer:=buffer shr (7 - pi mod 8);
      (HeightMap+255-pi)^:=buffer and $00000000000001ff;
    end;
  freemem(tmp,36*8);
  (HeightMap+256)^:=255;

end;

function TChunk_Block.ExtractHeightMap_1_13(tree:TATree):boolean;
begin
  FWS[256]:=0;
  FWSW[256]:=0;
  FOF[256]:=0;
  FOFW[256]:=0;
  FMB[256]:=0;
  FMBN[256]:=0;
  tree.CurrentInto(tree.root.Achild.first.obj as TATreeUnit);
  if not tree.CurrentInto('Level') then exit;
  tree.CurrentInto('Heightmaps');

  if tree.CurrentInto('OCEAN_FLOOR_WG') then
    begin
      case tree.Current.size of
        37:MonoHeightMap_1_16(tree.Current,@FOFW[0]);
        36:MonoHeightMap_1_13(tree.Current,@FOFW[0]);
        else begin assert(false,'HeightMap长度不是36或37。');exit end;
      end;
      tree.CurrentOut;
    end;
  if tree.CurrentInto('WORLD_SURFACE_WG') then
    begin
      case tree.Current.size of
        37:MonoHeightMap_1_16(tree.Current,@FWSW[0]);
        36:MonoHeightMap_1_13(tree.Current,@FWSW[0]);
        else begin assert(false,'HeightMap长度不是36或37。');exit end;
      end;
      tree.CurrentOut;
    end;
  if tree.CurrentInto('OCEAN_FLOOR') then
    begin
      case tree.Current.size of
        37:MonoHeightMap_1_16(tree.Current,@FOF[0]);
        36:MonoHeightMap_1_13(tree.Current,@FOF[0]);
        else begin assert(false,'HeightMap长度不是36或37。');exit end;
      end;
      tree.CurrentOut;
    end;
  if tree.CurrentInto('WORLD_SURFACE') then
    begin
      case tree.Current.size of
        37:MonoHeightMap_1_16(tree.Current,@FWS[0]);
        36:MonoHeightMap_1_13(tree.Current,@FWS[0]);
        else begin assert(false,'HeightMap长度不是36或37。');exit end;
      end;
      tree.CurrentOut;
    end;
  if tree.CurrentInto('MOTION_BLOCKING_NO_LEAVES') then
    begin
      case tree.Current.size of
        37:MonoHeightMap_1_16(tree.Current,@FMBN[0]);
        36:MonoHeightMap_1_13(tree.Current,@FMBN[0]);
        else begin assert(false,'HeightMap长度不是36或37。');exit end;
      end;
      tree.CurrentOut;
    end;
  if tree.CurrentInto('MOTION_BLOCKING') then
    begin
      case tree.Current.size of
        37:MonoHeightMap_1_16(tree.Current,@FMB[0]);
        36:MonoHeightMap_1_13(tree.Current,@FMB[0]);
        else begin assert(false,'HeightMap长度不是36或37。');exit end;
      end;
      tree.CurrentOut;
    end;

  result:=true;
end;

function TChunk_Block.LoadFromTree(tree:TATree):boolean;
begin
  result:=false;
  if not OnlyOneChunk(tree) then exit;
  ExtractChunkPos(tree);
  ExtractBiomes(tree);

  if HasHeightMaps(tree) then begin
    if not ExtractHeightMap_1_13(tree) then exit;
  end else begin
    if not ExtractHeightMap_164(tree) then exit;
  end;

  if HasPalette(tree) then begin
    if not ExtractBlocks_1_13(tree) then exit;
  end else begin
    if not ExtractBlocks_164(tree) then exit;
  end;



  result:=true;
end;

procedure TChunk_Block.SaveToFile(filename:string);
var f:text;
begin
  assignfile(f,filename);
  rewrite(f);
  write(f,'[');
  FStream.Position:=0;
  while FStream.Position<FStream.Size do
    begin
      if FStream.Position<>0 then write(f,',');
      write(f,'[');
      write(f,FStream.ReadByte);
      write(f,',');
      write(f,FStream.ReadByte);
      write(f,',');
      write(f,FStream.ReadByte);
      write(f,',');
      write(f,FStream.ReadByte);
      write(f,']');
    end;
  write(f,']');
  closefile(f);
end;
procedure TChunk_Block.SaveByteToFile(filename:string);
begin
  FStream.SaveToFile(filename);
end;
procedure TChunk_Block.SaveHeightMapToFile(filename:string);
var f:text;
    procedure PrintOneMap(mapname:string;p:pword);
    var pi:integer;
    begin
      write(f,'"'+mapname+'"=>[');
      write(f,p^);
      for pi:=1 to 255 do
        begin
          write(f,',');
          write(f,(p+pi)^);
        end;
      write(f,'],');
    end;

begin
  assignfile(f,filename);
  rewrite(f);
  write(f,'{');
  if FWS[256]<>0 then PrintOneMap('WORLD_SURFACE',@FWS[0]);
  if FWSW[256]<>0 then PrintOneMap('WORLD_SURFACE_WG',@FWSW[0]);
  if FOF[256]<>0 then PrintOneMap('OCEAN_FLOOR',@FOF[0]);
  if FOFW[256]<>0 then PrintOneMap('OCEAN_FLOOR_WG',@FOFW[0]);
  if FMB[256]<>0 then PrintOneMap('MOTION_BLOCKING',@FMB[0]);
  if FMBN[256]<>0 then PrintOneMap('MOTION_BLOCKING_NO_LEAVES',@FMBN[0]);
  write(f,'}');
  closefile(f);
end;


constructor TChunk_Block.Create;
begin
  inherited Create;
  FStream:=TMemoryStream.Create;
  FBiomes:=TMemoryStream.Create;
  FMB[256]:=0;
  FMBN[256]:=0;
  FOF[256]:=0;
  FOFW[256]:=0;
  FWS[256]:=0;
  FWSW[256]:=0;
end;

destructor TChunk_Block.Destroy;
begin
  FStream.Free;
  FBiomes.Free;
  inherited Destroy;
end;


end.

