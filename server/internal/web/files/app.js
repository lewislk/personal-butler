// PersonalButler · Web 表单录入前端
// 零依赖、原生 JS。配置存在 localStorage，所有 API 调用带 X-Device-ID + X-Sync-Token。
(function () {
  "use strict";

  const LS_KEY = "pb_web_cfg";
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);

  const cfg = loadCfg();

  // ---------- 工具函数 ----------

  function loadCfg() {
    try {
      const raw = localStorage.getItem(LS_KEY);
      if (raw) return JSON.parse(raw);
    } catch (e) { /* ignore */ }
    return { deviceId: "", syncToken: "" };
  }
  function saveCfg() {
    localStorage.setItem(LS_KEY, JSON.stringify(cfg));
  }

  function toast(msg, type) {
    const el = $("#toast");
    el.textContent = msg;
    el.className = "toast " + (type || "");
    setTimeout(() => { el.className = "toast hidden"; }, 2200);
  }

  async function apiCall(path, method, body) {
    if (!cfg.deviceId) {
      openSettings();
      throw new Error("请先在配置中填写 Device ID");
    }
    const headers = {
      "Content-Type": "application/json",
      "X-Device-ID": cfg.deviceId,
      "X-Sync-Token": cfg.syncToken || "",
    };
    const opts = { method, headers };
    if (body !== undefined) opts.body = JSON.stringify(body);
    const resp = await fetch(path, opts);
    let json;
    try { json = await resp.json(); } catch (e) {
      throw new Error("服务端返回非 JSON（HTTP " + resp.status + "）");
    }
    if (json.code !== 0) {
      const err = new Error(json.msg || ("code=" + json.code));
      err.code = json.code;
      throw err;
    }
    return json.data;
  }

  // 把 <input type="file"> 选中的图片读成 base64 字符串
  // 同时把图片缩到 512px 内（用 canvas），控制 payload 大小；保持 JPEG 0.7 质量
  // 与客户端 ImageProcessor.swift 的约定一致。
  function fileToBase64(file) {
    return new Promise((resolve, reject) => {
      if (!file) return resolve(null);
      const reader = new FileReader();
      reader.onload = (e) => {
        const img = new Image();
        img.onload = () => {
          const MAX = 512;
          let { width, height } = img;
          if (width > height && width > MAX) {
            height = Math.round(height * MAX / width);
            width = MAX;
          } else if (height > MAX) {
            width = Math.round(width * MAX / height);
            height = MAX;
          }
          const canvas = document.createElement("canvas");
          canvas.width = width;
          canvas.height = height;
          const ctx = canvas.getContext("2d");
          ctx.drawImage(img, 0, 0, width, height);
          // JPEG 0.7，与 iOS 端约定一致
          const dataUrl = canvas.toDataURL("image/jpeg", 0.7);
          // 剥离 "data:image/jpeg;base64," 前缀，与服务端约定一致
          resolve(dataUrl.split(",")[1]);
        };
        img.onerror = () => reject(new Error("图片解析失败"));
        img.src = e.target.result;
      };
      reader.onerror = () => reject(new Error("文件读取失败"));
      reader.readAsDataURL(file);
    });
  }

  // ---------- 配置面板 ----------

  function openSettings() {
    $("#cfg-device-id").value = cfg.deviceId;
    $("#cfg-sync-token").value = cfg.syncToken;
    $("#settings-panel").classList.remove("hidden");
  }
  function closeSettings() {
    $("#settings-panel").classList.add("hidden");
  }

  $("#btn-settings").addEventListener("click", openSettings);
  $("#btn-close-cfg").addEventListener("click", closeSettings);
  $("#btn-save-cfg").addEventListener("click", () => {
    cfg.deviceId = $("#cfg-device-id").value.trim();
    cfg.syncToken = $("#cfg-sync-token").value.trim();
    saveCfg();
    closeSettings();
    toast("配置已保存", "success");
    refreshList();
  });

  // ---------- 列表 ----------

  let recipes = [];
  let currentId = null;

  async function refreshList() {
    if (!cfg.deviceId) {
      $("#recipe-list").innerHTML = '<p class="empty">请先在配置中填写 Device ID</p>';
      openSettings();
      return;
    }
    $("#recipe-list").innerHTML = '<p class="empty">加载中…</p>';
    try {
      recipes = await apiCall("/api/recipes", "GET");
      renderList();
    } catch (e) {
      $("#recipe-list").innerHTML = '<p class="empty">加载失败：' + escapeHtml(e.message) + "</p>";
    }
  }

  function renderList() {
    const wrap = $("#recipe-list");
    if (!recipes || recipes.length === 0) {
      wrap.innerHTML = '<p class="empty">还没有菜谱，点击右上角「+ 新建」开始</p>';
      return;
    }
    wrap.innerHTML = "";
    recipes.forEach((r) => {
      const item = document.createElement("div");
      item.className = "recipe-item" + (r.id === currentId ? " active" : "");
      item.innerHTML =
        '<span class="emoji">' + escapeHtml(r.emoji || "🍲") + "</span>" +
        '<span class="name">' + escapeHtml(r.name) + "</span>" +
        '<span class="meta">' + (r.minutes || 0) + "min · " + escapeHtml(difficultyLabel(r.difficulty)) + "</span>";
      item.addEventListener("click", () => loadRecipe(r.id));
      wrap.appendChild(item);
    });
  }

  function difficultyLabel(v) {
    return ({ easy: "简单", medium: "中等", hard: "进阶" })[v] || v;
  }

  function escapeHtml(s) {
    if (s == null) return "";
    return String(s).replace(/[&<>"']/g, (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }

  // ---------- 表单 ----------

  function showForm() { $("#form-wrap").classList.remove("hidden"); $("#form-empty").classList.add("hidden"); }
  function hideForm() { $("#form-wrap").classList.add("hidden"); $("#form-empty").classList.remove("hidden"); }

  function resetForm() {
    $("#recipe-form").reset();
    $("#f-id").value = "";
    $("#f-emoji").value = "🍲";
    $("#f-difficulty").value = "easy";
    $("#f-minutes").value = "30";
    $("#f-category").value = "home";
    $("#f-icon").value = "";
    $("#icon-preview").classList.add("hidden");
    $("#icon-preview").src = "";
    $("#btn-delete").classList.add("hidden");
    renderIngredients([]);
  }

  function renderIngredients(ings) {
    const list = $("#ingredients-list");
    list.innerHTML = "";
    (ings || []).forEach((ing) => addIngredientRow(ing));
  }
  function addIngredientRow(ing) {
    const row = document.createElement("div");
    row.className = "ing-row";
    row.innerHTML =
      '<label><span>名称</span><input type="text" class="ing-name" placeholder="番茄" /></label>' +
      '<label><span>用量</span><input type="text" class="ing-amount" placeholder="2 个" /></label>' +
      '<label><span>顺序</span><input type="number" class="ing-order" min="0" /></label>' +
      '<button type="button" class="btn ghost small del-ing">删除</button>';
    row.querySelector(".ing-name").value = ing ? (ing.name || "") : "";
    row.querySelector(".ing-amount").value = ing ? (ing.amount || "") : "";
    row.querySelector(".ing-order").value = ing ? (ing.order != null ? ing.order : "") : "";
    row.querySelector(".del-ing").addEventListener("click", () => row.remove());
    $("#ingredients-list").appendChild(row);
  }
  $("#btn-add-ing").addEventListener("click", () => addIngredientRow(null));

  function collectIngredients() {
    const rows = $$("#ingredients-list .ing-row");
    const out = [];
    let order = 0;
    rows.forEach((r) => {
      const name = r.querySelector(".ing-name").value.trim();
      const amount = r.querySelector(".ing-amount").value.trim();
      const orderStr = r.querySelector(".ing-order").value;
      // 顺序：用户填了就用，没填就按行号兜底
      const o = orderStr !== "" ? parseInt(orderStr, 10) : order;
      order++;
      if (!name && !amount) return; // 跳过完全空行
      out.push({ name, amount, order: isNaN(o) ? 0 : o });
    });
    return out;
  }

  async function collectForm() {
    const id = $("#f-id").value || null;
    const iconFile = $("#f-icon").files[0];
    let iconBase64 = null;
    if (iconFile) {
      iconBase64 = await fileToBase64(iconFile);
    } else if ($("#icon-preview").src && !$("#icon-preview").classList.contains("hidden")) {
      // 已存在图片且未替换：把现有 base64 取出来（编辑场景下从 dataURL 解析）
      const src = $("#icon-preview").src;
      if (src.startsWith("data:")) {
        iconBase64 = src.split(",")[1];
      } else {
        // 服务端返回的 iconImageBase64 是裸 base64，前端展示时手动加了 dataURL 前缀
        iconBase64 = $("#icon-preview").dataset.raw || null;
      }
    }
    return {
      id: id, // 创建时为 null；编辑时为原 id
      name: $("#f-name").value.trim(),
      emoji: $("#f-emoji").value.trim() || "🍲",
      difficulty: $("#f-difficulty").value,
      minutes: parseInt($("#f-minutes").value, 10) || 0,
      category: $("#f-category").value,
      steps: $("#f-steps").value,
      tips: $("#f-tips").value,
      ingredientsLegacyRaw: $("#f-legacy").value,
      iconImageBase64: iconBase64,
      ingredients: collectIngredients(),
    };
  }

  $("#btn-new").addEventListener("click", () => {
    currentId = null;
    resetForm();
    showForm();
    renderList();
  });

  $("#btn-cancel").addEventListener("click", () => {
    hideForm();
    currentId = null;
    renderList();
  });

  $("#btn-delete").addEventListener("click", async () => {
    if (!currentId) return;
    if (!confirm("确认删除该菜谱？该操作不可撤销。")) return;
    try {
      await apiCall("/api/recipes/" + encodeURIComponent(currentId), "DELETE");
      toast("已删除", "success");
      currentId = null;
      hideForm();
      refreshList();
    } catch (e) {
      toast("删除失败：" + e.message, "error");
    }
  });

  // 图片选择 → 预览
  $("#f-icon").addEventListener("change", async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    try {
      const base64 = await fileToBase64(file);
      $("#icon-preview").src = "data:image/jpeg;base64," + base64;
      $("#icon-preview").dataset.raw = base64;
      $("#icon-preview").classList.remove("hidden");
    } catch (err) {
      toast("图片处理失败：" + err.message, "error");
    }
  });
  $("#btn-clear-icon").addEventListener("click", () => {
    $("#f-icon").value = "";
    $("#icon-preview").src = "";
    $("#icon-preview").dataset.raw = "";
    $("#icon-preview").classList.add("hidden");
  });

  $("#recipe-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const btn = $("#btn-save");
    btn.disabled = true;
    btn.textContent = "保存中…";
    try {
      const payload = await collectForm();
      if (!payload.name) {
        toast("请填写名称", "error");
        return;
      }
      let savedId;
      if (payload.id) {
        await apiCall("/api/recipes/" + encodeURIComponent(payload.id), "PUT", payload);
        savedId = payload.id;
      } else {
        const data = await apiCall("/api/recipes", "POST", payload);
        savedId = data && data.id;
      }
      toast("已保存", "success");
      currentId = savedId;
      await refreshList();
      // 重新加载保存后的菜谱到表单，让用户看到最新状态
      await loadRecipe(savedId);
    } catch (e) {
      toast("保存失败：" + e.message, "error");
    } finally {
      btn.disabled = false;
      btn.textContent = "保存";
    }
  });

  async function loadRecipe(id) {
    currentId = id;
    renderList();
    try {
      const r = await apiCall("/api/recipes/" + encodeURIComponent(id), "GET");
      $("#f-id").value = r.id;
      $("#f-name").value = r.name || "";
      $("#f-emoji").value = r.emoji || "🍲";
      $("#f-difficulty").value = r.difficulty || "easy";
      $("#f-minutes").value = r.minutes || 0;
      $("#f-category").value = r.category || "home";
      $("#f-steps").value = r.steps || "";
      $("#f-tips").value = r.tips || "";
      $("#f-legacy").value = r.ingredientsLegacyRaw || "";
      // 图标
      if (r.iconImageBase64) {
        $("#icon-preview").src = "data:image/jpeg;base64," + r.iconImageBase64;
        $("#icon-preview").dataset.raw = r.iconImageBase64;
        $("#icon-preview").classList.remove("hidden");
      } else {
        $("#icon-preview").src = "";
        $("#icon-preview").dataset.raw = "";
        $("#icon-preview").classList.add("hidden");
      }
      $("#f-icon").value = "";
      // 食材
      renderIngredients(r.ingredients || []);
      $("#btn-delete").classList.remove("hidden");
      showForm();
    } catch (e) {
      toast("加载失败：" + e.message, "error");
    }
  }

  // ---------- 启动 ----------

  refreshList();
  if (!cfg.deviceId) openSettings();
})();
