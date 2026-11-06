-- TileID names/values verified against the supplied 1.4.5.8 dump.
local M={}
local trees={[5]=true,[72]=true,[170]=true,[323]=true,[571]=true,[583]=true,[584]=true,[585]=true,[586]=true,[587]=true,[588]=true,[589]=true,[596]=true,[616]=true,[634]=true}
-- v1.2.3: 378 目标假人已放开（纯方块，无独立实体）
local unsupported={[128]=true,[269]=true,[334]=true,[395]=true,[423]=true,[470]=true,[471]=true,[475]=true,[520]=true,[597]=true,[698]=true,[723]=true,[724]=true}
function M.tree(id)return trees[id]==true end
function M.container(id)return id==21 or id==88 or id==467 end
function M.unsupported(id)return unsupported[id]==true end
-- Vanilla placement helpers use bottom anchors; verified in ARM64 PlaceDoor,
-- Place1x2, Place2x1, Place3x2 and PlaceChest implementations.
local legacy={ [10]={0,2,1,3},[14]={1,1,3,2},[15]={0,1,1,2},[16]={0,0,2,1},[17]={1,1,3,2},[18]={0,0,2,1},[21]={0,1,2,2} }
function M.origin(id)return legacy[id]end
return M
