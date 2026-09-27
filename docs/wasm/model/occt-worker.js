'use strict';

let runtimePromise = null;
let runtimeKey = '';

const normalizeMeshArrays = result => {
  const transfer = [];
  for (const mesh of result?.meshes || []) {
    const position = Float32Array.from(mesh?.attributes?.position?.array || []);
    mesh.attributes = mesh.attributes || {};
    mesh.attributes.position = { array: position };
    transfer.push(position.buffer);

    if (mesh.attributes.normal?.array) {
      const normal = Float32Array.from(mesh.attributes.normal.array);
      mesh.attributes.normal = { array: normal };
      transfer.push(normal.buffer);
    }

    const index = Uint32Array.from(mesh?.index?.array || []);
    mesh.index = { array: index };
    transfer.push(index.buffer);
  }
  return transfer;
};

const getRuntime = (runtimeUrl, wasmUrl) => {
  const key = `${runtimeUrl}\n${wasmUrl}`;
  if (runtimePromise && runtimeKey === key) {
    return runtimePromise;
  }
  runtimeKey = key;
  runtimePromise = Promise.resolve().then(() => {
    if (typeof self.occtimportjs !== 'function') {
      importScripts(runtimeUrl);
    }
    if (typeof self.occtimportjs !== 'function') {
      throw new Error('The OCCT runtime did not expose occtimportjs().');
    }
    return self.occtimportjs({
      locateFile(path) {
        return path.endsWith('.wasm') ? wasmUrl : new URL(path, runtimeUrl).href;
      },
    });
  });
  runtimePromise.catch(() => {
    runtimePromise = null;
    runtimeKey = '';
  });
  return runtimePromise;
};

const readGeometry = (occt, format, bytes, params) => {
  switch (format) {
    case 'step':
      return occt.ReadStepFile(bytes, params);
    case 'iges':
      return occt.ReadIgesFile(bytes, params);
    case 'brep':
      return occt.ReadBrepFile(bytes, params);
    default:
      throw new Error(`Unsupported OCCT geometry format: ${format}`);
  }
};

self.addEventListener('message', async event => {
  const { id, format, buffer, params, runtimeUrl, wasmUrl } = event.data || {};
  try {
    if (!id || !(buffer instanceof ArrayBuffer) || !runtimeUrl || !wasmUrl) {
      throw new Error('Invalid geometry worker request.');
    }
    const occt = await getRuntime(runtimeUrl, wasmUrl);
    const result = readGeometry(occt, format, new Uint8Array(buffer), params || null);
    const transfer = normalizeMeshArrays(result);
    self.postMessage({ id, ok: true, result }, transfer);
  } catch (error) {
    self.postMessage({
      id,
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    });
  }
});
