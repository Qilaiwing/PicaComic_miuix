class CopyManga extends ComicSource {
    // 拷贝漫画 —— PicaComic_MIUIX 内置源
    // 参考 wgh136/pica_configs (MIT, Copyright (c) 2024 wgh136) 的 copy_manga.js 结构。
    // 3.0.0 起改用官方 App 接口 (/api/v3)，大陆网络无需代理即可获取章节。

    name = "拷贝漫画"

    key = "copy_manga"

    version = "3.2.5"

    minAppVersion = "4.0.0"

    url = "https://raw.githubusercontent.com/Qilaiwing/PicaComic_miuix/miuix/assets/comic_sources/copy_manga.js"

    // 设置项（PicaComic_MIUIX 的 JS 源设置格式，在 设置 - 漫画源 中显示）
    settings = {
favorites_ordering: {
            title: "收藏排序方式",
            type: "select",
            options: [
                { value: "-datetime_updated", text: "更新时间" },
                { value: "-datetime_modifier", text: "收藏时间" },
                { value: "-datetime_browse", text: "阅读时间" },
            ],
            default: "-datetime_updated",
        },
        region: {
            title: "CDN线路",
            type: "select",
            options: [
                { value: "1", text: "大陆线路" },
                { value: "0", text: "海外线路" },
            ],
            default: "1",
        },
        image_quality: {
            title: "图片质量",
            type: "select",
            options: [
                { value: "800", text: "低 (800)" },
                { value: "1200", text: "中 (1200)" },
                { value: "1500", text: "高 (1500)" },
            ],
            default: "1500",
        },
        search_api: {
            title: "搜索方式",
            type: "select",
            options: [
                { value: "baseAPI", text: "基础API" },
                { value: "webAPI", text: "网页端API" },
            ],
            default: "baseAPI",
        },
        base_url: {
            title: "API地址",
            type: "input",
            // 留空 = 自动（从 network2 获取）
            placeholder: "自动",
            validator: "^$|^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$",
            default: "",
        },
        refresh_base_url: {
            title: "从网络获取API地址",
            type: "callback",
            buttonText: "刷新",
            callback: async () => {
                let host = await this.fetchHost()
                if (!host) throw "获取失败"
                let s = this.loadData("settings") || {}
                s.base_url = host
                this.saveData("settings", s)
                return host
            }
        },
        clear_device_info: {
            title: "清除设备信息",
            type: "callback",
            buttonText: "清除",
            callback: () => {
                this.clearDeviceInfo()
                return "ok"
            }
        },
        auto_clear_device_info: {
            title: "每次请求后自动清除设备信息",
            type: "switch",
            default: false,
        },
    }

    static appVersion = "3.0.6"
    // App 请求签名用的密钥（官方客户端公开常量）
    static signKey = "3af08590311032efe0660550a0563a53"
    static fallbackHost = "api.copy202601.com"

    get region() {
        return this.loadSetting("region") || "1"
    }

    get token() {
        return this.loadData("token")
    }

    // 设备标识首次使用时随机生成并保存
    persistent(name, gen) {
        let v = this.loadData(name)
        if (!v) {
            v = gen()
            this.saveData(name, v)
        }
        return v
    }

    get deviceIds() {
        const pick = (s) => s[Math.floor(Math.random() * s.length)]
        const L = "ABCDEFGHIJKLMNOPQRSTUVWXYZ", D = "0123456789"
        const nd = (n) => Array.from({ length: n }, () => pick(D)).join("")
        return {
            device: this.persistent("_device", () => pick(L) + pick(L) + pick(D) + pick(L) + "." + nd(6) + "." + nd(3)),
            deviceinfo: this.persistent("_deviceinfo", () => `${1000000 + Math.floor(Math.random() * 9000000)}V-${1000 + Math.floor(Math.random() * 9000)}`),
            pseudoid: this.persistent("_pseudoid", () => Array.from({ length: 16 }, () => pick(L + L.toLowerCase() + D)).join("")),
        }
    }

    get headers() {
        let now = new Date()
        let ts = String(Math.floor(now.getTime() / 1000))
        let pad = (n) => String(n).padStart(2, "0")
        let ids = this.deviceIds
        let v = CopyManga.appVersion
        return {
            "User-Agent": `COPY/${v}`,
            "source": "copyApp",
            "version": v,
            "platform": "3",
            "referer": `com.copymanga.app-${v}`,
            "dt": `${now.getFullYear()}.${pad(now.getMonth() + 1)}.${pad(now.getDate())}`,
            "device": ids.device,
            "deviceinfo": ids.deviceinfo,
            "pseudoid": ids.pseudoid,
            "umstring": "b4c89ca4104ea9a97750314d791520ac",
            "Accept": "application/json",
            "region": this.region,
            "authorization": this.token ? `Token ${this.token}` : "Token",
            "x-auth-timestamp": ts,
            "x-auth-signature": Convert.hmacSha256Hex(CmUtil.utf8Bytes(CopyManga.signKey), CmUtil.utf8Bytes(ts)),
        }
    }

    clearDeviceInfo() {
        this.deleteData("_device")
        this.deleteData("_deviceinfo")
        this.deleteData("_pseudoid")
    }

    afterRequest() {
        // 登录过程中保持设备指纹稳定，避免每次请求换号触发风控
        if (this._keepDevice) return
        if (this.loadSetting("auto_clear_device_info") === true) this.clearDeviceInfo()
    }

    async get(url) {
        try { return await Network.get(url, this.headers) } finally { this.afterRequest() }
    }

    async post(url, headers, body) {
        try { return await Network.post(url, headers, body) } finally { this.afterRequest() }
    }

    async fetchHost() {
        try {
            let res = await this.get("https://api.copy-manga.com/api/v3/system/network2?platform=3")
            if (res.status === 200) return JSON.parse(res.body).results.api[0][0] || null
        } catch (e) {}
        return null
    }

    // 网页端搜索接口路径会变动，从搜索页读取并缓存 12 小时
    async webSearchPath() {
        let c = this.loadData("_web_search")
        if (c && c.path && Date.now() - c.time < 12 * 3600 * 1000) return c.path
        let path = "/api/kb/web/searchcl/comics"
        try {
            let res = await Network.get("https://www.mangacopy.com/search", { "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36" })
            let m = res.status === 200 ? res.body.match(/const countApi = "([^"]+)"/) : null
            if (m) path = m[1]
        } catch (e) {}
        this.saveData("_web_search", { path: path, time: Date.now() })
        return path
    }

    // API 地址：用户填写优先；留空时从 network2 获取并缓存 12 小时
    async apiBase() {
        let s = String(this.loadSetting("base_url") || "").trim().replace(/^https?:\/\//, "").replace(/\/.*$/, "")
        if (s && s !== "auto") return `https://${s}/api/v3`
        let cached = this.loadData("_api_host")
        if (cached && cached.host && Date.now() - cached.time < 12 * 3600 * 1000) {
            return `https://${cached.host}/api/v3`
        }
        let host = (await this.fetchHost()) || CopyManga.fallbackHost
        this.saveData("_api_host", { host: host, time: Date.now() })
        return `https://${host}/api/v3`
    }

    // 大陆线路需要广告接口下发的 request_id
    async requestId() {
        if (this.region === "0") return ""
        try {
            let res = await this.get("https://marketing.aiacgn.com/api/v2/adopr/query3/?format=json&ident=200100001", this.headers)
            if (res.status === 200) return JSON.parse(res.body).results.request_id ?? ""
        } catch (e) {}
        return ""
    }

    async getJson(path) {
        let res = await this.get(`${await this.apiBase()}${path}`)
        let data = null
        try { data = JSON.parse(res.body) } catch (e) {}
        if (res.status !== 200 || !data || data.code !== 200) {
            if (res.status !== 200) {
                // 域名失效时下次重新获取
                this.deleteData("_api_host")
            }
            throw data?.message ?? `Invalid status code: ${res.status}`
        }
        return data.results
    }

    parseComic(e) {
        if (e.comic) e = e.comic
        return {
            id: e.path_word,
            title: e.name,
            subTitle: (e.author ?? []).map(a => a.name).join(" "),
            cover: e.cover,
            tags: (e.theme ?? []).map(t => t.name).filter(t => t),
            description: e.datetime_updated ?? ""
        }
    }

    async loadComics(query, page) {
        let r = await this.getJson(`/comics?limit=21&offset=${(page - 1) * 21}&${query}`)
        return {
            comics: r.list.map(e => this.parseComic(e)),
            maxPage: Math.max(1, Math.ceil(r.total / 21))
        }
    }

    // 账号：官方 App 登录接口，token 放在 authorization 请求头
    account = {
        login: async (account, pwd) => {
            // 官方 App 登录表单：password 为 base64(utf8(pwd-salt))，其后紧跟换行再接 salt。
            // 不要对 username/password 做 encodeURIComponent（+ 需按字面提交）。
            let salt = String(1000 + Math.floor(Math.random() * 9000))
            let password = CmUtil.base64(CmUtil.utf8Bytes(`${pwd}-${salt}`))
            let body = `username=${account}&password=${password}\n&salt=${salt}&authorization=Token+`
            let headers = {
                ...this.headers,
                "authorization": "Token",
                "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
            }

            // 候选主机：network2 最新 → 用户配置 → 内置 fallback（旧域名常对 /login 直接 210/断连）
            let hosts = []
            let push = (h) => {
                h = String(h || "").trim().replace(/^https?:\/\//, "").replace(/\/.*$/, "")
                if (h && !hosts.includes(h)) hosts.push(h)
            }
            try { push(await this.fetchHost()) } catch (e) {}
            push(this.loadSetting("base_url"))
            push(CopyManga.fallbackHost)
            // 兼容仍能浏览的旧节点，但放最后
            push("api.copy2000.online")

            this._keepDevice = true
            let lastError = null
            try {
                for (let host of hosts) {
                    let res
                    try {
                        res = await this.post(`https://${host}/api/v3/login`, headers, body)
                    } catch (e) {
                        lastError = String(e)
                        this.deleteData("_api_host")
                        continue
                    }
                    let data = null
                    try { data = JSON.parse(res.body) } catch (e) {}
                    if (data && data.code === 200 && data.results && data.results.token) {
                        this.saveData("token", data.results.token)
                        this.saveData("username", data.results.username ?? account)
                        this.saveData("_api_host", { host: host, time: Date.now() })
                        // 登录成功的域名写回设置，避免下次仍打到已风控的旧节点
                        let st = this.loadData("settings") || {}
                        st.base_url = host
                        this.saveData("settings", st)
                        return "ok"
                    }
                    let msg = data?.message ?? data?.results?.detail ?? `Invalid status code: ${res.status}`
                    lastError = msg
                    // 210：破解检测/设备风控 —— 清设备指纹后换下一主机
                    if (data && data.code === 210) {
                        this.clearDeviceInfo()
                        headers = {
                            ...this.headers,
                            "authorization": "Token",
                            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
                        }
                        continue
                    }
                    // 其它业务错误（密码错误等）无需换主机
                    if (res.status === 200 || (data && data.code && data.code !== 200)) {
                        throw msg
                    }
                }
            } finally {
                this._keepDevice = false
                this.afterRequest()
            }
            throw lastError ?? "登录失败"
        },
        logout: () => {
            this.deleteData("token")
            this.deleteData("username")
        },
        registerWebsite: "https://www.mangacopy.com/web/login/loginByAccount",
        // 检查凭证：返回 { valid, username }
        checkStatus: async () => {
            if (!this.token) return { valid: false, username: null }
            // 用收藏列表接口校验 token 是否有效
            let res = await this.get(`${await this.apiBase()}/member/collect/comics?limit=1&offset=0&free_type=1&ordering=-datetime_updated`)
            let data = null
            try { data = JSON.parse(res.body) } catch (e) {}
            let name = this.loadData("username")
            if (res.status === 200 && data && data.code === 200) return { valid: true, username: name }
            if (res.status === 401 || res.status === 403) return { valid: false, username: name }
            throw data?.message ?? `Invalid status code: ${res.status}`
        },
    }

    favorites = {
        multiFolder: false,
        addOrDelFavorite: async (comicId, folderId, isAdding) => {
            let rid = await this.requestId()
            let r = await this.getJson(`/comic2/${comicId}?in_mainland=true&request_id=${rid}&platform=3`)
            let body = `comic_id=${r.comic.uuid}&is_collect=${isAdding ? 1 : 0}&authorization=Token+${this.token ?? ""}`
            let res = await this.post(`${await this.apiBase()}/member/collect/comic`, {
                ...this.headers,
                "Content-Type": "application/x-www-form-urlencoded;charset=utf-8",
            }, body)
            if (res.status === 401) throw "Login expired"
            let data = null
            try { data = JSON.parse(res.body) } catch (e) {}
            if (res.status !== 200 || !data || data.code !== 200) throw data?.message ?? `Invalid status code: ${res.status}`
            return "ok"
        },
        loadComics: async (page, folder) => {
            let ordering = this.loadSetting("favorites_ordering") || "-datetime_updated"
            let res = await this.get(`${await this.apiBase()}/member/collect/comics?limit=21&offset=${(page - 1) * 21}&free_type=1&ordering=${ordering}`)
            if (res.status === 401) throw "Login expired"
            let data = null
            try { data = JSON.parse(res.body) } catch (e) {}
            if (res.status !== 200 || !data || data.code !== 200) throw data?.message ?? `Invalid status code: ${res.status}`
            return {
                comics: data.results.list.map(e => this.parseComic(e)),
                maxPage: Math.max(1, Math.ceil(data.results.total / 21))
            }
        }
    }

    init() {}

    explore = [
        {
            title: "拷贝漫画 热门",
            type: "multiPageComicList",
            load: async (page) => this.loadComics("ordering=-popular", page)
        },
        {
            title: "拷贝漫画 最新",
            type: "multiPageComicList",
            load: async (page) => this.loadComics("ordering=-datetime_updated", page)
        }
    ]

    category = {
        title: "拷贝漫画",
        parts: [
            {
                name: "题材",
                type: "fixed",
                categories: ["全部", "爱情", "欢乐向", "冒险", "奇幻", "百合", "校园", "科幻", "东方", "生活", "格斗", "轻小说", "悬疑", "治愈", "竞技", "恐怖", "萌系", "其他"],
                itemType: "category",
                categoryParams: ["", "aiqing", "huanlexiang", "maoxian", "qihuan", "baihe", "xiaoyuan", "kehuan", "dongfang", "shenghuo", "gedou", "qingxiaoshuo", "xuanyi", "zhiyu", "jingji", "kongbu", "mengxi", "qita"]
            }
        ],
        enableRankingPage: false,
    }

    categoryComics = {
        load: async (category, param, options, page) => {
            let q = `ordering=${options[0]}`
            if (param) q += `&theme=${param}`
            return this.loadComics(q, page)
        },
        optionList: [
            {
                options: [
                    "-popular-热门",
                    "-datetime_updated-最新更新",
                ]
            }
        ]
    }

    search = {
        load: async (keyword, options, page) => {
            let q = encodeURIComponent(keyword)
            let r
            if (this.loadSetting("search_api") === "webAPI") {
                let res = await this.get(`https://www.mangacopy.com${await this.webSearchPath()}?offset=${(page - 1) * 21}&platform=2&limit=21&q=${q}&q_type=`)
                let data = null
                try { data = JSON.parse(res.body) } catch (e) {}
                if (res.status !== 200 || !data || data.code !== 200) throw data?.message ?? `Invalid status code: ${res.status}`
                r = data.results
            } else {
                r = await this.getJson(`/search/comic?limit=21&offset=${(page - 1) * 21}&q=${q}&q_type=&platform=3`)
            }
            return {
                comics: r.list.map(e => this.parseComic(e)),
                maxPage: Math.max(1, Math.ceil(r.total / 21))
            }
        },
        optionList: []
    }


    async previewImages(comicId, chapters) {
        if (!chapters || chapters.size !== 1) return null
        let first = null
        for (let k of chapters.keys()) { first = k; break }
        if (!first) return null
        try {
            let images = (await this.comic.loadEp(comicId, first)).images
            return images && images.length ? images.slice(0, 20) : null
        } catch (e) {
            return null
        }
    }


    async loadEpWithRetry(comicId, epId) {
        let lastError = null
        for (let i = 0; i < 3; i++) {
            try {
                return await this.comic._loadEpOnce(comicId, epId)
            } catch (e) {
                // Login-required should not be retried away
                if (String(e).includes("登录") || String(e).includes("登")) throw e
                lastError = e
                await new Promise(r => setTimeout(r, 500 * (i + 1)))
            }
        }
        throw lastError
    }

    comic = {
        loadInfo: async (id) => {
            let rid = await this.requestId()
            let r = await this.getJson(`/comic2/${id}?in_mainland=true&request_id=${rid}&platform=3`)
            let c = r.comic
            let groups = Object.values(r.groups ?? {})
            let chapters = new Map()
            for (let g of groups) {
                let prefix = groups.length > 1 && g.path_word !== "default" ? `[${g.name}] ` : ""
                let offset = 0, total = 1
                while (offset < total) {
                    let list = await this.getJson(`/comic/${id}/group/${g.path_word}/chapters?limit=100&offset=${offset}&in_mainland=true&request_id=${rid}`)
                    total = list.total
                    for (let e of list.list) chapters.set(e.uuid, prefix + e.name)
                    if (list.list.length === 0) break
                    offset += list.list.length
                }
            }
            if (chapters.size === 0) throw "未获取到章节"
            let tags = {}
            let authors = (c.author ?? []).map(e => e.name)
            if (authors.length) tags["作者"] = authors
            if (c.status?.display) tags["状态"] = [c.status.display]
            if (c.datetime_updated) tags["更新"] = [c.datetime_updated]
            let themes = (c.theme ?? []).map(e => e.name).filter(e => e)
            if (themes.length) tags["标签"] = themes
            return {
                title: c.name,
                cover: c.cover,
                description: c.brief ?? "",
                tags: tags,
                chapters: chapters,
                isFavorite: null,
                subId: c.uuid,
                thumbnails: await this.previewImages(id, chapters)
            }
        },
        loadEp: async (comicId, epId) => this.loadEpWithRetry(comicId, epId),
        _loadEpOnce: async (comicId, epId) => {
            let rid = await this.requestId()
            let r
            try {
                r = await this.getJson(`/comic/${comicId}/chapter2/${epId}?in_mainland=true&request_id=${rid}`)
            } catch (e) {
                if (!this.token && String(e).includes("登"))
                    throw "该章节需要登录后查看，请在 设置 - 漫画源 - 拷贝漫画 - 账号 中登录"
                throw e
            }
            let ch = r.chapter
            let q = this.loadSetting("image_quality") || "1500"
            let urls = ch.contents.map(e => e.url.replace(/([./])c\d+x\.[a-zA-Z]+$/, `$1c${q}x.webp`))
            // words 给出每张图在章节中的实际位置；有空洞/越界则回退原序
            let images = urls.slice()
            if (Array.isArray(ch.words) && ch.words.length === urls.length) {
                let reordered = new Array(urls.length)
                let valid = true
                for (let i = 0; i < urls.length; i++) {
                    let w = ch.words[i]
                    if (typeof w !== "number" || w < 0 || w >= urls.length || reordered[w] != null) {
                        valid = false
                        break
                    }
                    reordered[w] = urls[i]
                }
                if (valid && reordered.every(x => x != null)) images = reordered
            }
            return { images: images }
        },
        onImageLoad: (url, comicId, epId) => {
            return { headers: { "User-Agent": `COPY/${CopyManga.appVersion}` } }
        },

        onThumbnailLoad: (url) => {
            return { headers: { "User-Agent": `COPY/${CopyManga.appVersion}` } }
        },

        // 评论：subId 为漫画 uuid；replyTo 为楼层 id 时加载楼中楼
        loadComments: async (comicId, subId, page, replyTo) => {
            let uuid = subId
            if (!uuid) uuid = (await this.getJson(`/comic2/${comicId}?platform=3`)).comic.uuid
            let limit = 20
            let r = await this.getJson(`/comments?comic_id=${uuid}&limit=${limit}&offset=${(page - 1) * limit}&reply_id=${replyTo || ""}`)
            let comments = (r.list || []).map(e => ({
                userName: e.user_name || "匿名",
                avatar: e.user_avatar || null,
                content: e.parent_user_name && replyTo ? `回复 @${e.parent_user_name}：${e.comment}` : e.comment,
                time: e.create_at,
                replyCount: replyTo ? null : (e.count || 0),
                id: String(e.id),
            }))
            return { comments: comments, maxPage: Math.max(1, Math.ceil((r.total || 0) / limit)) }
        },

        sendComment: async (comicId, subId, content, replyTo) => {
            if (!this.token) throw "请先登录拷贝漫画"
            let uuid = subId
            if (!uuid) uuid = (await this.getJson(`/comic2/${comicId}?platform=3`)).comic.uuid
            let body = `comic_id=${encodeURIComponent(uuid)}&comment=${encodeURIComponent(content)}&reply_id=${replyTo || ""}`
            let headers = Object.assign({}, this.headers, { "Content-Type": "application/x-www-form-urlencoded;charset=utf-8" })
            let res = await this.post(`${await this.apiBase()}/member/comment`, headers, body)
            if (res.status === 401) throw "Login expired"
            let data = null
            try { data = JSON.parse(res.body) } catch (e) {}
            if (!data || data.code !== 200) throw "发送失败：" + (data?.message ?? res.status)
            return true
        }
    }
}

let CmUtil = {
    utf8Bytes(s) {
        const r = []
        for (const ch of unescape(encodeURIComponent(s))) r.push(ch.charCodeAt(0))
        return r
    },
    base64(bytes) {
        const t = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        let out = ""
        for (let i = 0; i < bytes.length; i += 3) {
            let n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0)
            out += t[(n >> 18) & 63] + t[(n >> 12) & 63]
            out += i + 1 < bytes.length ? t[(n >> 6) & 63] : "="
            out += i + 2 < bytes.length ? t[n & 63] : "="
        }
        return out
    },
}
