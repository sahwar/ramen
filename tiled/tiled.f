[section] preamble
$10000 [version] tiled-ver
\ Tiled module for RAMEN

[undefined] draw-ver [if] $000100 include ramen/lib/draw [then]
[undefined] array2d-ver [if] $000100 include ramen/lib/array2d [then]

\ -------------------------------------------------------------------------------------------------
[section] buffers

10000 constant #MAXTILES
include ramen/tiled/tilegame
1024 1024 array2d: tilebuf
#MAXTILES cellstack: recipes
100 cellstack: bitmaps        \ single-image tileset's bitmaps

\ -------------------------------------------------------------------------------------------------
[section] tilemap

\ Tilemap objects
\ A large singular 2D array is used for stability

var scrollx  var scrolly  \ used to define starting column and row!
var w  var h              \ width & height in pixels

: /tilemap
    displaywh w 2!
    draw>
        at@ w 2@ clip>
        scrollx 2@  20 20 scroll  tilebuf loc  tilebuf pitch@  tilemap ;

: /isotilemap
    draw>
        scrollx 2@  20 20 scroll  tilebuf loc  tilebuf pitch@  50 50 isotilemap ;

: map@  ( col row -- tile )  tilebuf loc @ ;

: >gid  ( tile -- gid )  $0000fffc and 10 << ;

\ hex addressing
: hmap@  ( #col #row -- tile ) 2p map@ ;

include ramen/tiled/collision

var onhitmap  \ XT;  ( info -- )  must be assigned to something to enable tilemap collision detection

\ map hitbox; exclusively for colliding with the TILEBUF; expressed in relative coords
var mbx  var mby  var mbw  var mbh

: onhitmap>  ( -- <code> ) r> code> onhitmap ! ;

: collide-objects-map  ( objlist tilesize -- )
    locals| tilesize |
    each>   x 2@  mbx 2@ x 2+!  onhitmap @ if  mbw 2@  tilesize  onhitmap @ collide-map  then
            x 2! ;

\ -------------------------------------------------------------------------------------------------
[section] tmx

$10000 include ramen/tiled/tmx

also xmling  also tmxing

var gid

: @gidbmp  ( -- bitmap )  tiles gid @ [] @ ;

\ Image (background) object support (multi-image tileset) -----------------------------------------
: (loadbitmaps)  ( map n -- dom )
    tileset[]  locals| gid0 ts |
    ts eachelement> that's tile  dup tile>bmp  tiles rot id@ gid0 + [] ! ;

: loadbitmaps  ( map n -- )  (loadbitmaps)  ?dom-free ;

\ Load a single-image tileset ---------------------------------------------------------------------
: loadtileset  ( map n -- ) \ load bitmap and split it up, adding it to the global tileset
    tileset[] over tileset>bmp locals| bmp firstgid ts dom |
    bmp bitmaps push
    bmp  ts tilewh@  firstgid maketiles
    dom ?dom-free ;

\ don't execute this frequently!
: @tilesetwh  ( map n -- tw th )  tileset[] drop tilewh@ rot ?dom-free ;

\ Load a normal tilemap and convert it for RAMEN to be able to use --------------------------------
: de-Tiled  ( n -- n )
    dup 2 << over $80000000 and 1 >> or swap $40000000 and 1 << or ;

: loadtilemap  ( layer destcol destrow -- )
    3dup
        tilebuf loc  tilebuf pitch@ readlayer
        rot wh@ tilebuf some2d> cells bounds do   \ convert it!
            i @ de-Tiled i !
        cell +loop ;

\ Load object recipes from tileset ----------------------------------------------------------------
\ No images are loaded in this use case.
\ Instead we load any object recipes that aren't loaded.

\ Load object groups ------------------------------------------------------------------------------
\ This supports 3 kinds of objects that can be stored in TMX files.
\ 1) Regular scripted game objects where the tile gid points to a recipe XT in a table.
\ 2) Rectangular objects with no associated tile
\ 3) Background (image) objects where the gid points to a bitmap in the global tileset

\ You are responsible for assigning these DEFERs before calling LOAD-OBJECTS
\ They all can expect the pen has already been set to the XY position.

defer tmxobj   ( object-nnn XT -- )   \ XT is the TMX recipe for the object loaded from the script
defer tmxrect  ( object-nnn w h -- )
defer tmximage ( object-nnn gid -- )

: -recipes  ( -- )  recipes 0 [] #MAXTILES cells erase ;

\ : reload-recipes ;

\ Define a TMX recipe.  TMXING is in the search order while compiling.
\ All TMX recipe definitions are kept in the TMXING vocabulary.
get-order get-current
    define (;)   : ;   previous previous definitions  postpone ;   ; immediate
set-current set-order


0 value (rcp)
: :TMX  ( -- <name> )  ( object-nnn -- )  \ name must match the filename
    also (;)  also tmxing definitions
    >in @
    defined rot >in !  not if  drop create here to (rcp) 0 ,
                           else  >body to (rcp) then
    :noname (rcp) ! ;

\ LOADRECIPES
\ Conditionally load recipes that aren't defined and then stores them in RECIPES
\ Tile image source paths are important!  They correspond to the object script filenames!
\ When a tile does not have an image, it will load a recipe if the tile
\ has its TYPE set to something.

: uncount  drop #1 - ;
: (saveorder)  get-order  r> call  >r  set-order  r> ;
: >recipe  ( name c -- recipe|0 )
    \ cr 2dup type
    locals| c name |
    (saveorder)
    only tmxing  name c uncount  find  ( xt|a flag )  ?exit
    drop  tmxpath count s[  " objects/" +s  name c +s  " .f" +s  ]s  slashes
        2dup file-exists 0= if  2drop 0 exit  then
        only forth definitions
        included  (rcp) ;

: (loadrecipe)  ( gid name c -- )  >recipe  swap recipes nth ! ;

: (loadrecipes)  tileset[]  locals| firstgid |
    ( tileset ) eachelement> that's tile
        dup  id@ firstgid +  swap
            0 " image" element ?dup if
                source@ -path -ext (loadrecipe)
            else
                ?type if  (loadrecipe)  else  ( gid ) drop  then
            then ;
: loadrecipes  ( map n -- )  (loadrecipes)  ?dom-free ;

: loadobjects  ( objgroup -- )
    eachelement> that's object
        dup xy@ at
        dup rectangle? if
            dup wh@ ( nnn w h ) tmxrect
        else
            dup gid@ dup  recipes nth @ ?dup if
                ( nnn gid recipe ) nip  @ ( nnn xt ) tmxobj
            else
                ( nnn gid ) tmximage
            then
        then
;

: -bitmaps  bitmaps sbounds do  i @ -bmp  cell +loop  bitmaps 0 truncate ;

: loadnewtmx  ( adr c -- dom map )
    -recipes  -tiles  -bitmaps  loadtmx ;

only forth definitions