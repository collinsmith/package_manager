#include <amxmodx>
#include <amxmisc>
#include <logger>

#pragma ctrlchar 94
#include "../lib/curl/amx_includes/curl_consts.inc"
#include "../lib/curl/amx_includes/curl.inc"
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

static AMXX_DATADIR[PLATFORM_MAX_PATH];
static TMP_DIR[PLATFORM_MAX_PATH], TMP_DIR_LENGTH;

public plugin_natives() {
  register_library("package_manager");

  register_native("pkg_processManifest", "native_processManifest");
}

public plugin_init() {
  register_plugin("AMXX Package Manager", VERSION_STRING, "Tirant");

  createTmpDir();
  new manifest[PLATFORM_MAX_PATH];
  getPath(manifest, charsmax(manifest), AMXX_DATADIR, "manifest");
  curl(MANIFEST_URL, manifest, "onManifestDownloaded");
}

stock getBuildId(buildId[], len) {
  return formatex(buildId, len, "%s [%s]", VERSION_STRING, __DATE__);
}

createTmpDir() {
  if (isStringEmpty(AMXX_DATADIR)) {
    get_datadir(AMXX_DATADIR, charsmax(AMXX_DATADIR));
    TMP_DIR_LENGTH = createPath(TMP_DIR, charsmax(TMP_DIR), AMXX_DATADIR, "tmp");
  }
}

stock curl(const url[], const dst[], const callback[], Trie: trie = Invalid_Trie) {
#if defined DEBUG_CURL
  server_print("curl \"%s\" \"%s\"", url, dst);
#endif

  if (!trie) {
    trie = TrieCreate();
  }
  
  TrieSetString(trie, "path", dst);
  
  new data[2];
  data[0] = fopen(dst, "wb");
  data[1] = any:(trie);

  new CURL: curl = curl_easy_init();
  curl_easy_setopt(curl, CURLOPT_BUFFERSIZE, BUFFER_SIZE + 1);
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, data[0]);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, "onCurlWrite");
  curl_easy_perform(curl, callback, data, sizeof data);
}

public onCurlWrite(data[], size, nmemb, file) {
  new actual_size = size * nmemb;
  fwrite_blocks(file, data, actual_size, BLOCK_CHAR);
  return actual_size;
}

public onManifestDownloaded(CURL: curl, CURLcode: code, data[]) {
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
  new file = fopen(path, "rt");
  if (!file) {
    server_print("Failed to open \"%s\". Aborting update.", path);
    return;
  }

  new buffer[BUFFER_SIZE + 1];
  new plugin[32], version[32], url[256], checksum[256];
  while (!feof(file) && fgets(file, buffer, charsmax(buffer)) > 1) {
    parse(buffer, plugin, charsmax(plugin), version, charsmax(version), url, charsmax(url), checksum, charsmax(checksum));

    server_print("searching for %s...", plugin);
    new pluginId = find_plugin_byfile(plugin);
    if (pluginId) {
      server_print("%s=%d", plugin, pluginId);
      server_print("checking versions...");
      new currentVersion[32];
      get_plugin(pluginId, .version=currentVersion, .len3=charsmax(currentVersion));
      new result = compareVersions(currentVersion, version);
      if (result == 0) {
        server_print("current version matches the requested version");
        continue;
      } else if (result < 0) {
        server_print("you have a newer version (yours: %s, update: %s)", currentVersion, version);
        continue;
      }

      server_print("update available (yours: %s, update: %s)", currentVersion, version);
    }

    server_print("downloading update...");

    new Trie: trie = TrieCreate();
    TrieSetString(trie, "plugin", plugin);
    TrieSetString(trie, "version", version);
    TrieSetString(trie, "url", url);
    TrieSetString(trie, "checksum", checksum);
    TrieSetString(trie, "path", path);
    server_print("%s %s %s %s", plugin, version, url, checksum);
    
    createTmpDir();
    resolvePath(TMP_DIR, charsmax(TMP_DIR), TMP_DIR_LENGTH, plugin);
    curl(url, TMP_DIR, "onPluginDownloaded", trie);
  }

  fclose(file);
}

public onPluginDownloaded(CURL: curl, CURLcode: code, data[]) {
  fclose(data[0]);
  curl_easy_cleanup(curl);
  
  new Trie: trie = Trie:(data[1]);

  new path[256];
  TrieGetString(trie, "path", path, charsmax(path));

  if (code != CURLE_OK) {
    log_error(AMX_ERR_GENERAL, "Error downloading \"%s\": %d", path, code);
    return;
#if defined DEBUG_MANIFEST
  } else {
    server_print("Download completed: \"%s\"", path);
#endif
  }

  new checksum[256];
  TrieGetString(trie, "checksum", checksum, charsmax(checksum));
  server_print("checksum=%s", checksum);
  
  server_print("hashing %s...", path);

  new hash[256];
  hash_file(path, Hash_Md5, hash, charsmax(hash));
  server_print("hash=%s", hash);

  if (!isStringEmpty(checksum) && equal(hash, checksum)) {
    server_print("hashes do not match, aborting...");
    return;
  }
  
  new plugin[32];
  TrieGetString(trie, "plugin", plugin, charsmax(plugin));

  new transfer[256];
  formatex(transfer, charsmax(transfer), "addons/amxmodx/plugins/%s", plugin);

  server_print("hashes match, installing update...");
  rename_file(path, transfer, 1);
}

stock compareVersions(const current[], const other[]) {
  new trash1[32], trash2[32];
  new p1, v1[8], p2, v2[8];
  
  new a, b;
  new i;
  for (;;) {
    p1 = strtok2(current[a], v1, charsmax(v1), trash1, charsmax(trash1), '.', TRIM_FULL);
    p2 = strtok2(other[b], v2, charsmax(v2), trash2, charsmax(trash2), '.', TRIM_FULL);
    if (p1 != -1 && p2 != -1) {
      i = str_to_num(v2) - str_to_num(v1);
      if (i != 0) {
        return i;
      }

      a += p1 + 1;
      b += p2 + 1;
    } else if (p1 != -1) {
      return -1;
    } else if (p2 != -1) {
      return 1;
    } else {
      i = str_to_num(v2) - str_to_num(v1);
      return i;
    }
  }

  return 0;
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
  
  createTmpDir();
  resolvePath(TMP_DIR, charsmax(TMP_DIR), TMP_DIR_LENGTH, file);
  curl(url, TMP_DIR, "onManifestDownloaded");
}
