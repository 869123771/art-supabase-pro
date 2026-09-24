import{r as e}from"./rolldown-runtime-DAXXjFlN.js";import{B as t,Q as n,Z as r,rt as i}from"./user-xuA5_W3a.js";import"./supabase-BgxBaIXK.js";import{t as a}from"./pagination-DVzefm8X.js";import{n as o}from"./tree-Cneimgdp.js";var s=e({addDict:()=>D,addDictType:()=>v,deleteDict:()=>T,deleteDictBatch:()=>E,deleteDictType:()=>_,deleteResource:()=>j,editDict:()=>O,editDictType:()=>y,executeSql:()=>F,fetchDatabaseMetadata:()=>M,fetchDictTypeIdByDictionaryId:()=>S,fetchGetDictDirectoryTree:()=>g,fetchGetDictList:()=>C,fetchGetDictListByTypeCode:()=>w,fetchGetDictListByTypeId:()=>x,fetchGetDictTypeList:()=>m,fetchGetDictionaryTypeOptions:()=>h,fetchGetResourceList:()=>k,generateSqlByAi:()=>I,renameResource:()=>A,saveDictTypeTreeOrder:()=>b}),{supabase:c,keysToSnakeDeep:l,responseHandle:u}=n(),d=500,f=new o({idKey:`id`,parentKey:`parentId`,childrenKey:`children`});function p(e){let t=Array.isArray(e)?e[0]:e;return t&&typeof t==`object`?t:null}async function m(e={}){let{name:t}=e,n=[{col:`name`,op:`ilike`,val:t?`%${t}%`:void 0}],r=c.from(`sys_dict_type`).select(`*, cascade_parent_type:dict_type_cascade_parent(id, name, code)`).order(`sort`,{ascending:!0}).order(`name`,{ascending:!0});return r=i(r,n,{skipEmpty:!0,camelToSnake:!1}),await u(()=>r,{})}async function h(e={}){let t=c.from(`sys_dict_type`).select(`id, name, code, cascade_parent_type_id`).eq(`node_type`,`dictionary`).eq(`status`,`1`).order(`name`,{ascending:!0});return e.excludeId&&(t=t.neq(`id`,e.excludeId)),await u(()=>t,{showErrorMessage:!0})}async function g(e={}){let t=await u(()=>c.from(`sys_dict_type`).select(`id, parent_id, node_type, name, code, status, sort`).eq(`node_type`,`directory`).order(`sort`,{ascending:!0}).order(`name`,{ascending:!0}),{showErrorMessage:!0}),n=f.listToTree(t.data??[],(e,t)=>Number(e.sort??0)-Number(t.sort??0)||e.name.localeCompare(t.name,`zh-CN`)),r=e.excludeId?f.removeNodesByCondition(n,t=>t.id===e.excludeId).tree:n;return{...t,data:r}}async function _(e){let{id:t}=e;return await u(()=>c.from(`sys_dict_type`).delete({count:`exact`}).eq(`id`,t),{showMessage:!0,requireAffected:!0,noAffectedMessage:r})}async function v(e){return await u(()=>c.from(`sys_dict_type`).insert(l(e)),{showMessage:!0,breakReturn:!0})}async function y(e){let{id:t,...n}=e;return await u(()=>c.from(`sys_dict_type`).update(l(n),{count:`exact`}).eq(`id`,t),{showMessage:!0,breakReturn:!0,requireAffected:!0,noAffectedMessage:r})}async function b(e){return await u(()=>c.rpc(`save_dict_type_tree_order`,{p_updates:e}),{breakReturn:!0,showMessage:!1})}async function x(e){let{typeId:t,label:n=``,code:r,i18nScope:a,status:o,recordId:s}=e,l=[{col:`id`,op:`eq`,val:s},{col:`typeId`,op:`eq`,val:t},{col:`label`,op:`ilike`,val:`%${n}%`},{col:`code`,op:`eq`,val:r},{col:`i18nScope`,op:`eq`,val:a},{col:`status`,op:`eq`,val:o}],d=c.from(`sys_dictionary`).select(`*`,{count:`exact`}).order(`sort`,{ascending:!0}).order(`label`,{ascending:!0});return d=i(d,l,{skipEmpty:!0,camelToSnake:!0}),await u(()=>d,{})}async function S(e){let{data:t}=await u(()=>c.from(`sys_dictionary`).select(`type_id`).eq(`id`,e).maybeSingle(),{});return t?.typeId}async function C(){return await a(({from:e,to:t})=>{let n=c.from(`sys_dictionary`).select(`
          id,
          type_id,
          code,
          label,
          value,
          sort,
          color,
          tag_type,
          remark,
          parent_id,
          cascade_parent_id,
          dict_type_table:sys_dict_type!inner(
            code,
            name
          )
        `).eq(`status`,`1`).eq(`dict_type_table.status`,`1`).order(`sort`,{ascending:!0}).order(`id`,{ascending:!0}).range(e,t);return u(()=>n,{})},{pageSize:d})}async function w(e){return await u(()=>c.from(`sys_dictionary`).select(`
          id,
          type_id,
          code,
          label,
          value,
          sort,
          color,
          tag_type,
          remark,
          parent_id,
          cascade_parent_id,
          dict_type_table:sys_dict_type!inner(
            code,
            name
          )
        `).eq(`status`,`1`).eq(`dict_type_table.status`,`1`).eq(`dict_type_table.code`,e).order(`sort`,{ascending:!0}).order(`id`,{ascending:!0}),{})}async function T(e){let{id:t}=e;return await u(()=>c.from(`sys_dictionary`).delete({count:`exact`}).eq(`id`,t),{showMessage:!0,requireAffected:!0,noAffectedMessage:r})}async function E(e){return await u(()=>c.from(`sys_dictionary`).delete({count:`exact`}).in(`id`,e),{showMessage:!0,requireAffected:!0,noAffectedMessage:r})}async function D(e){return await u(()=>c.from(`sys_dictionary`).insert(l(e)),{showMessage:!0,breakReturn:!0})}async function O(e){let{id:t,...n}=e;return await u(()=>c.from(`sys_dictionary`).update(l(n),{count:`exact`}).eq(`id`,t),{showMessage:!0,breakReturn:!0,requireAffected:!0,noAffectedMessage:r})}async function k(e){let{originName:t=``,suffix:n=``,from:r=0,to:a=9}=e,o=[{col:`originName`,op:`ilike`,val:`%${t}%`}];if(n){let e=n.split(`,`).map(e=>e.trim()).filter(e=>e.length>0);e.length>0&&o.push({col:`suffix`,op:`in`,val:e})}let s=c.from(`sys_attachment`).select(`*`,{count:`exact`}).order(`create_time`,{ascending:!1}).range(r,a);return s=i(s,o,{skipEmpty:!0,camelToSnake:!0}),await u(()=>s,{showErrorMessage:!0})}async function A(e){let{id:t,originName:n}=e;return await u(()=>c.from(`sys_attachment`).update({origin_name:n},{count:`exact`}).eq(`id`,t),{breakReturn:!0,requireAffected:!0,noAffectedMessage:r,errorMessage:`附件重命名失败，请稍后重试`})}async function j(e){let{id:t}=e,{data:n}=await u(()=>c.from(`sys_attachment`).select().eq(`id`,t).single(),{});if(!n)throw Error(`未找到待删除的附件`);let{storagePath:i,objectName:a}=n;if(await u(()=>c.from(`sys_attachment`).delete({count:`exact`}).eq(`id`,t),{breakReturn:!0,requireAffected:!0,noAffectedMessage:r,errorMessage:`附件删除失败，请稍后重试`}),!i||!a)return{storageCleanupFailed:!1};let o=`${i}/${a}`,{error:s}=await c.storage.from(`attachments`).remove([o]);return s?(console.warn(`[AttachmentCleanup] 附件记录已删除，但存储对象清理失败:`,s),{storageCleanupFailed:!0}):{storageCleanupFailed:!1}}async function M(){try{let[{data:e,error:n},r]=await Promise.all([t(`execute-sql-with-columns`,{body:{action:`metadata`}}),P()]);if(n||!e)return{...await N(),foreignKeys:r};let i=p(e),a=i?.schemas??[],o=(i?.columns??[]).map(e=>({tableSchema:e.tableSchema||``,tableName:e.tableName||``,columnName:e.columnName||``,dataType:e.dataType||``,isNullable:e.isNullable||`YES`,ordinalPosition:e.ordinalPosition||0})),s=new Map;return o.forEach(e=>{let t=`${e.tableSchema}.${e.tableName}`;s.has(t)||s.set(t,{tableSchema:e.tableSchema,tableName:e.tableName,columns:[]}),s.get(t).columns.push({name:e.columnName,dataType:e.dataType,isNullable:e.isNullable===`YES`})}),{schemas:a,columns:o,tables:Array.from(s.values()),functions:(i?.functions??[]).map(e=>({routineSchema:e.routineSchema||``,routineName:e.routineName||``,returnType:e.returnType||``})),foreignKeys:r}}catch(e){return console.error(`Failed to fetch database metadata:`,e),{schemas:[`public`],columns:[],tables:[],functions:[],foreignKeys:[]}}}async function N(){return{schemas:[`public`],columns:[],tables:[],functions:[],foreignKeys:[]}}async function P(){let{data:e,error:t}=await F({query:`
    SELECT
      tc.table_schema AS source_schema,
      tc.table_name AS source_table,
      kcu.column_name AS source_column,
      ccu.table_schema AS target_schema,
      ccu.table_name AS target_table,
      ccu.column_name AS target_column,
      tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.constraint_schema = tc.constraint_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    ORDER BY tc.table_schema, tc.table_name, tc.constraint_name
  `}),n=e?.rows;return t||!n?[]:n.map(e=>({sourceSchema:e.sourceSchema||e.source_schema||``,sourceTable:e.sourceTable||e.source_table||``,sourceColumn:e.sourceColumn||e.source_column||``,targetSchema:e.targetSchema||e.target_schema||``,targetTable:e.targetTable||e.target_table||``,targetColumn:e.targetColumn||e.target_column||``,constraintName:e.constraintName||e.constraint_name||``}))}async function F(e){return await u(()=>t(`execute-sql-with-columns`,{body:e}),{convertToCamelShadow:!0,returnRawError:!0})}async function I(e){return await u(()=>t(`ai-sql-assistant`,{body:e}),{convertToCamelShadow:!0,returnRawError:!0})}export{k as _,E as a,b,O as c,M as d,S as f,h as g,m as h,T as i,y as l,x as m,v as n,_ as o,g as p,s as r,j as s,D as t,F as u,I as v,A as y};