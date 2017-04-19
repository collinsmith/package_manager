#include <amxmodx>
#include <amxmisc>
#include <logger>

#pragma ctrlchar 94
#include "../lib/curl/curl_consts.inc"
#include "../lib/curl/curl.inc"
#pragma ctrlchar 92

#include "include/stocks/param_stocks.inc"
#include "include/stocks/path_stocks.inc"
#include "include/stocks/string_stocks.inc"

#define VERSION_ID 1
#define VERSION_STRING "1.0.0"

#define BUFFER_SIZE 511

#define DEBUG_NATIVES
#define DEBUG_MANIFEST
#define DEBUG_CURL

static const MANIFEST_URL[] = "https://raw.githubusercontent.com/collinsmith/package_manager/master/manifest";

public plugin_natives() {
  register_library("package_manager");

  register_native("pkg_processManifest", "native_processManifest");
}

public plugin_init() {
  new buildId[32];
  getBuildId(buildId, charsmax(buildId));
  register_plugin("AMXX Package Manager", buildId, "Tirant");

  new manifest[256];
  get_datadir(manifest, charsmax(manifest));
  BuildPath(manifest, charsmax(manifest), manifest, "manifest");
  curl(MANIFEST_URL, manifest);
}

stock getBuildId(buildId[], len) {
  return formatex(buildId, len, "%s [%s]", VERSION_STRING, __DATE__);
}

stock curl(const url[], const dst[]) {
#if defined DEBUG_CURL
  server_print("curl \"%s\" \"%s\"", url, dst);
#endif

  new Trie: trie = TrieCreate();
  TrieSetString(trie, "path", dst);
  
  new data[2];
  data[0] = fopen(dst, "wb");
  data[1] = any:(trie);

  new CURL: curl = curl_easy_init();
  curl_easy_setopt(curl, CURLOPT_BUFFERSIZE, BUFFER_SIZE + 1);
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, data[0]);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, "onCurlWrite");
  curl_easy_perform(curl, "onCurlCompleted", data, sizeof data);
}

public onCurlWrite(data[], size, nmemb, file) {
  new actual_size = size * nmemb;
  fwrite_blocks(file, data, actual_size, BLOCK_CHAR);
  return actual_size;
}

public onCurlCompleted(CURL: curl, CURLcode: code, data[]) {
  fclose(data[0]);
  curl_easy_cleanup(curl);

  new path[256];
  new Trie: trie = Trie:(data[1]);
  TrieGetString(trie, "path", path, charsmax(path));
  assert !isStringEmpty(path);

  if (code != CURLE_OK) {
    log_error(AMX_ERR_GENERAL, "Error downloading \"%s\": %d", path, code);
    return;
#if defined DEBUG_MANIFEST
  } else {
    server_print("Download completed: \"%s\"", path);
#endif
  }
  
  processManifest(path);
}

processManifest(path[]) {
}

/*******************************************************************************
 * Natives
 ******************************************************************************/

//native pkg_processManifest(const url[]);
public native_processManifest(plugin, numParams) {
#if defined DEBUG_NATIVES
  if (!numParamsEqual(1, numParams)) {
    return;
  }
#endif

  new url[256], len;
  len = get_string(1, url, charsmax(url));

  new file[32];
  new i = len - 1;
  for (; i && url[i] != '/'; i--) {}
  len = copy(file, charsmax(file), url[i + 1]);
  formatex(file[len], charsmax(file) - len, "_%d", plugin);
  
  new manifest[256];
  get_datadir(manifest, charsmax(manifest));
  BuildPath(manifest, charsmax(manifest), manifest, file);
  curl(url, manifest);
}
