class MangaDex extends ComicSource {
    // MangaDex —— PicaComic_MIUIX 内置源（基于官方 API 独立编写）
    name = "MangaDex"

    key = "mangadex"

    version = "1.2.9"

    minAppVersion = "4.0.0"

    url = "https://raw.githubusercontent.com/Qilaiwing/PicaComic_miuix/miuix/assets/comic_sources/mangadex.js"

    settings = {
        language: {
            title: "章节语言",
            type: "select",
            options: [
                { value: "zh,zh-hk,en", text: "中文优先，英文备选" },
                { value: "zh,zh-hk", text: "仅中文" },
                { value: "en", text: "English" },
                { value: "ja", text: "日本語" },
                { value: "ko", text: "한국어" },
                { value: "zh,zh-hk,en,ja", text: "中/英/日" },
            ],
            default: "zh,zh-hk,en",
        },
        content_rating: {
            title: "内容分级",
            type: "select",
            options: [
                { value: "safe", text: "安全" },
                { value: "safe,suggestive", text: "安全 + 擦边" },
                { value: "safe,suggestive,erotica", text: "安全 + 擦边 + 情色" },
                { value: "safe,suggestive,erotica,pornographic", text: "全部" },
            ],
            default: "safe,suggestive",
        },
        image_quality: {
            title: "图片质量",
            type: "select",
            options: [
                { value: "data", text: "原图" },
                { value: "data-saver", text: "省流" },
            ],
            default: "data",
        },
title_language: {
            title: "标题语言",
            type: "select",
            options: [
                { value: "zh", text: "中文优先" },
                { value: "en", text: "英文优先" },
                { value: "ja-ro", text: "罗马音优先" },
            ],
            default: "zh",
        },
    }


    // 不提供账号登录（论坛发帖需官网登录，本源不支持）。
    api = "https://api.mangadex.org"

    get headers() {
        return { "User-Agent": "PicaComic_MIUIX/1.0" }
    }

    init() {}

    // ---------- 工具 ----------

    query(params) {
        let parts = []
        for (let k in params) {
            let v = params[k]
            if (v === undefined || v === null || v === "") continue
            if (Array.isArray(v)) {
                for (let item of v) parts.push(`${encodeURIComponent(k)}[]=${encodeURIComponent(item)}`)
            } else {
                parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
            }
        }
        return parts.join("&")
    }

    async getJson(path, params) {
        let url = this.api + path + (params ? "?" + this.query(params) : "")
        let lastError = null
        for (let i = 0; i < 2; i++) {
            try {
                let res = await Network.get(url, this.headers)
                if (res.status === 200) return JSON.parse(res.body)
                if (res.status === 429) {
                    lastError = "请求过于频繁，请稍后再试"
                    await new Promise(r => setTimeout(r, 1000 * (i + 1)))
                    continue
                }
                lastError = "Invalid status code: " + res.status
            } catch (e) {
                lastError = e
            }
            if (i < 1) await new Promise(r => setTimeout(r, 400 * (i + 1)))
        }
        throw lastError
    }

    setting(key, fallback) {
        let v = this.loadSetting(key)
        return v === undefined || v === null || v === "" ? fallback : v
    }

    get ratings() {
        return this.setting("content_rating", "safe,suggestive").split(",")
    }

    get languages() {
        return this.setting("language", "zh,zh-hk,en").split(",")
    }

    pickText(map) {
        if (!map) return ""
        let pref = this.setting("title_language", "zh")
        let order = pref === "zh" ? ["zh", "zh-hk", "en", "ja-ro", "ja"]
            : pref === "en" ? ["en", "ja-ro", "zh", "zh-hk", "ja"]
                : ["ja-ro", "en", "ja", "zh", "zh-hk"]
        for (let l of order) if (map[l]) return map[l]
        let keys = Object.keys(map)
        return keys.length ? map[keys[0]] : ""
    }

    pickTitle(attr) {
        // 主标题之外，altTitles 中可能有中文标题
        let all = Object.assign({}, attr.title || {})
        for (let alt of attr.altTitles || []) {
            for (let l in alt) if (!all[l]) all[l] = alt[l]
        }
        return this.pickText(all)
    }

    coverOf(manga, size) {
        let rel = (manga.relationships || []).find(r => r.type === "cover_art")
        let file = rel && rel.attributes ? rel.attributes.fileName : null
        if (!file) return ""
        return `https://uploads.mangadex.org/covers/${manga.id}/${file}${size ? "." + size + ".jpg" : ""}`
    }

    namesOf(manga, type) {
        return (manga.relationships || [])
            .filter(r => r.type === type && r.attributes)
            .map(r => r.attributes.name)
    }

    toComic(manga) {
        let a = manga.attributes || {}
        let tags = (a.tags || []).map(t => t.attributes.name.en)
        return {
            id: manga.id,
            title: this.pickTitle(a),
            cover: this.coverOf(manga, 256),
            subTitle: this.namesOf(manga, "author").join(", "),
            tags: tags,
            description: [a.year, this.statusText(a.status)].filter(e => e).join(" · "),
        }
    }

    statusText(s) {
        return { ongoing: "连载中", completed: "已完结", hiatus: "休刊", cancelled: "已取消" }[s] || s || ""
    }

    async listManga(params, page, pageSize) {
        let limit = pageSize || 20
        let res = await this.getJson("/manga", Object.assign({
            limit: limit,
            offset: (page - 1) * limit,
            includes: ["cover_art", "author"],
            contentRating: this.ratings,
        }, params))
        let total = Math.min(res.total || 0, 10000)
        return {
            comics: (res.data || []).map(m => this.toComic(m)),
            maxPage: Math.max(1, Math.ceil(total / limit)),
        }
    }

    // ---------- 探索 ----------

    explore = [
        {
            title: "MangaDex 热门",
            type: "multiPageComicList",
            load: async (page) => this.listManga({ "order[followedCount]": "desc", hasAvailableChapters: "true", availableTranslatedLanguage: this.languages }, page),
        },
        {
            title: "MangaDex 最新更新",
            type: "multiPageComicList",
            load: async (page) => this.listManga({ "order[latestUploadedChapter]": "desc", hasAvailableChapters: "true", availableTranslatedLanguage: this.languages }, page),
        },
        {
            title: "MangaDex 新作",
            type: "multiPageComicList",
            load: async (page) => this.listManga({ "order[createdAt]": "desc", hasAvailableChapters: "true", availableTranslatedLanguage: this.languages }, page),
        },
    ]

    // ---------- 分类（标签） ----------

    category = {
        title: "MangaDex",
        parts: [
            {
                "name": "类型",
                "type": "fixed",
                "categories": [
                    "动作",
                    "冒险",
                    "耽美",
                    "喜剧",
                    "犯罪",
                    "剧情",
                    "奇幻",
                    "百合",
                    "历史",
                    "恐怖",
                    "异世界",
                    "魔法少女",
                    "机甲",
                    "医疗",
                    "悬疑",
                    "哲学",
                    "心理",
                    "爱情",
                    "科幻",
                    "日常",
                    "运动",
                    "超级英雄",
                    "惊悚",
                    "悲剧",
                    "武侠"
                ],
                "itemType": "category",
                "categoryParams": [
                    "391b0423-d847-456f-aff0-8b0cfc03066b",
                    "87cc87cd-a395-47af-b27a-93258283bbc6",
                    "5920b825-4181-4a17-beeb-9918b0ff7a30",
                    "4d32cc48-9f00-4cca-9b5a-a839f0764984",
                    "5ca48985-9a9d-4bd8-be29-80dc0303db72",
                    "b9af3a63-f058-46de-a9a0-e0c13906197a",
                    "cdc58593-87dd-415e-bbc0-2ec27bf404cc",
                    "a3c67850-4684-404e-9b7f-c69850ee5da6",
                    "33771934-028e-4cb3-8744-691e866a923e",
                    "cdad7e68-1419-41dd-bdce-27753074a640",
                    "ace04997-f6bd-436e-b261-779182193d3d",
                    "81c836c9-914a-4eca-981a-560dad663e73",
                    "50880a9d-5440-4732-9afb-8f457127e836",
                    "c8cbe35b-1b2b-4a3f-9c37-db84c4514856",
                    "ee968100-4191-4968-93d3-f82d72be7e46",
                    "b1e97889-25b4-4258-b28b-cd7f4d28ea9b",
                    "3b60b75c-a2d7-4860-ab56-05f391bb889c",
                    "423e2eae-a7a2-4a8b-ac03-a8351462d71d",
                    "256c8bd9-4904-4360-bf4f-508a76d67183",
                    "e5301a23-ebd9-49dd-a0cb-2add944c7fe9",
                    "69964a64-2f90-4d33-beeb-f3ed2875eb4c",
                    "7064a261-a137-4d3a-8848-2d385de3a99c",
                    "07251805-a27e-4d59-b488-f0bfbec15168",
                    "f8f62932-27da-4fe4-8ee1-6779a8c5edba",
                    "acc803a4-c95a-4c22-86fc-eb6b582d82a2"
                ]
            },
            {
                "name": "题材",
                "type": "fixed",
                "categories": [
                    "Aliens",
                    "Animals",
                    "Cooking",
                    "Crossdressing",
                    "Delinquents",
                    "Demons",
                    "Genderswap",
                    "Ghosts",
                    "Gyaru",
                    "Harem",
                    "Incest",
                    "Loli",
                    "Mafia",
                    "Magic",
                    "Mahjong",
                    "Martial Arts",
                    "Military",
                    "Monster Girls",
                    "Monsters",
                    "Music",
                    "Ninja",
                    "Office Workers",
                    "Police",
                    "Post-Apocalyptic",
                    "Reincarnation",
                    "Reverse Harem",
                    "Samurai",
                    "School Life",
                    "Shota",
                    "Supernatural",
                    "Survival",
                    "Time Travel",
                    "Traditional Games",
                    "Vampires",
                    "Video Games",
                    "Villainess",
                    "Virtual Reality",
                    "Zombies"
                ],
                "itemType": "category",
                "categoryParams": [
                    "e64f6742-c834-471d-8d72-dd51fc02b835",
                    "3de8c75d-8ee3-48ff-98ee-e20a65c86451",
                    "ea2bc92d-1c26-4930-9b7c-d5c0dc1b6869",
                    "9ab53f92-3eed-4e9b-903a-917c86035ee3",
                    "da2d50ca-3018-4cc0-ac7a-6b7d472a29ea",
                    "39730448-9a5f-48a2-85b0-a70db87b1233",
                    "2bd2e8d0-f146-434a-9b51-fc9ff2c5fe6a",
                    "3bb26d85-09d5-4d2e-880c-c34b974339e9",
                    "fad12b5e-68ba-460e-b933-9ae8318f5b65",
                    "aafb99c1-7f60-43fa-b75f-fc9502ce29c7",
                    "5bd0e105-4481-44ca-b6e7-7544da56b1a3",
                    "2d1f5d56-a1e5-4d0d-a961-2193588b08ec",
                    "85daba54-a71c-4554-8a28-9901a8b0afad",
                    "a1f53773-c69a-4ce5-8cab-fffcd90b1565",
                    "cb562697-929f-4d28-9d66-6d3995bf2592",
                    "799c202e-7daa-44eb-9cf7-8a3c0441531e",
                    "ac72833b-c4e9-4878-b9db-6c8a4a99444a",
                    "dd1f77c5-dea9-4e2b-97ae-224af09caf99",
                    "36fd93ea-e8b8-445e-b836-358f02b3d33d",
                    "f42fbf9e-188a-447b-9fdc-f19dc1e4d685",
                    "489dd859-9b61-4c37-af75-5b18e88daafc",
                    "92d6d951-ca5e-429c-ac78-451071cbf064",
                    "df33b754-73a3-4c54-80e6-1a74a8058539",
                    "9467335a-1b83-4497-9231-765337a00b96",
                    "0bc90acb-ccc1-44ca-a34a-b9f3a73259d0",
                    "65761a2a-415e-47f3-bef2-a9dababba7a6",
                    "81183756-1453-4c81-aa9e-f6e1b63be016",
                    "caaa44eb-cd40-4177-b930-79d3ef2afe87",
                    "ddefd648-5140-4e5f-ba18-4eca4071d19b",
                    "eabc5b4c-6aff-42f3-b657-3e90cbd00b75",
                    "5fff9cde-849c-4d78-aab0-0d52b2ee1d25",
                    "292e862b-2d17-4062-90a2-0356caa4ae27",
                    "31932a7e-5b8e-49a6-9f12-2afa39dc544c",
                    "d7d1730f-6eb0-4ba6-9437-602cac38664c",
                    "9438db5a-7e2a-4ac0-b39e-e0d95a34b8a8",
                    "d14322ac-4d6f-4e9b-afd9-629d5f4d8a41",
                    "8c86611e-fab7-4986-9dec-d1a2f44acdd5",
                    "631ef465-9aba-4afb-b0fc-ea10efe274a8"
                ]
            },
            {
                "name": "形式",
                "type": "fixed",
                "categories": [
                    "4-Koma",
                    "Adaptation",
                    "Anthology",
                    "Award Winning",
                    "Doujinshi",
                    "Fan Colored",
                    "Full Color",
                    "Long Strip",
                    "Official Colored",
                    "Oneshot",
                    "Self-Published",
                    "Web Comic"
                ],
                "itemType": "category",
                "categoryParams": [
                    "b11fda93-8f1d-4bef-b2ed-8803d3733170",
                    "f4122d1c-3b44-44d0-9936-ff7502c39ad3",
                    "51d83883-4103-437c-b4b1-731cb73d786c",
                    "0a39b5a1-b235-4886-a747-1d05d216532d",
                    "b13b2a48-c720-44a9-9c77-39c9979373fb",
                    "7b2ce280-79ef-4c09-9b58-12b7c23a9b78",
                    "f5ba408b-0e7a-484d-8d49-4e9125ac96de",
                    "3e2b8dae-350e-4ab8-a8ce-016e844b9f0d",
                    "320831a8-4026-470b-94f6-8353740e6f04",
                    "0234a31e-a729-4e28-9d6a-3f87c4966b9e",
                    "891cf039-b895-47f0-9229-bef4c96eccd4",
                    "e197df38-d0e7-43b5-9b09-2842d0c326dd"
                ]
            }
        ],
        enableRankingPage: false,
    }

    categoryComics = {
        load: async (category, param, options, page) => {
            let params = { "includedTags": [param], availableTranslatedLanguage: this.languages, hasAvailableChapters: "true" }
            params[`order[${options[0] || "followedCount"}]`] = "desc"
            return this.listManga(params, page)
        },
        optionList: [
            {
                options: ["followedCount-最多关注", "latestUploadedChapter-最近更新", "rating-评分最高", "createdAt-最新加入"],
            }
        ],
    }

    // ---------- 搜索 ----------

    search = {
        load: async (keyword, options, page) => {
            let params = { title: keyword }
            params[`order[${options[0] || "relevance"}]`] = "desc"
            if (options[1] && options[1] !== "any") params.status = [options[1]]
            if (options[2] === "lang") params.availableTranslatedLanguage = this.languages
            return this.listManga(params, page)
        },
        optionList: [
            {
                label: "排序",
                options: ["relevance-相关度", "followedCount-最多关注", "latestUploadedChapter-最近更新", "rating-评分最高", "createdAt-最新加入"],
            },
            {
                label: "状态",
                options: ["any-全部", "ongoing-连载中", "completed-已完结", "hiatus-休刊", "cancelled-已取消"],
            },
            {
                label: "语言",
                options: ["lang-仅有所选语言章节", "all-不限"],
            },
        ],
    }

    favorites = null

    // ---------- 详情 / 章节 / 图片 ----------

    chapterTitle(ch) {
        let a = ch.attributes || {}
        let parts = []
        if (a.volume) parts.push(`Vol.${a.volume}`)
        if (a.chapter) parts.push(`Ch.${a.chapter}`)
        let name = parts.join(" ")
        if (a.title) name = name ? `${name} ${a.title}` : a.title
        if (!name) name = "Oneshot"
        if (this.languages.length > 1) name += ` [${a.translatedLanguage}]`
        let group = (ch.relationships || []).find(r => r.type === "scanlation_group" && r.attributes)
        if (group) name += ` - ${group.attributes.name}`
        return name
    }

    async loadChapters(id) {
        let all = []
        let offset = 0
        while (true) {
            let res = await this.getJson(`/manga/${id}/feed`, {
                limit: 500,
                offset: offset,
                translatedLanguage: this.languages,
                contentRating: ["safe", "suggestive", "erotica", "pornographic"],
                includes: ["scanlation_group"],
                includeExternalUrl: 0,
                "order[volume]": "asc",
                "order[chapter]": "asc",
            })
            all.push(...(res.data || []))
            offset += 500
            if (offset >= (res.total || 0) || offset >= 5000) break
        }
        // 同一话有多种语言时，按语言优先级只保留一个
        let rank = (l) => {
            let i = this.languages.indexOf(l)
            return i < 0 ? 99 : i
        }
        let best = new Map()
        let order = []
        for (let ch of all) {
            let a = ch.attributes
            if (a.pages === 0) continue
            let k = `${a.volume || ""}|${a.chapter || ch.id}`
            let prev = best.get(k)
            if (!prev) {
                best.set(k, ch)
                order.push(k)
            } else if (rank(a.translatedLanguage) < rank(prev.attributes.translatedLanguage)) {
                best.set(k, ch)
            }
        }
        let chapters = new Map()
        for (let k of order) {
            let ch = best.get(k)
            chapters.set(ch.id, this.chapterTitle(ch))
        }
        return chapters
    }

    // ---------- 评论（MangaDex 论坛讨论串） ----------

    forum = "https://forums.mangadex.org"

    get forumHeaders() {
        return { "User-Agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36" }
    }

    // 漫画对应的讨论串 id 与回复数（来自统计接口）
    async threadInfo(mangaId) {
        if (!this._threads) this._threads = {}
        if (this._threads[mangaId]) return this._threads[mangaId]
        let res = await this.getJson(`/statistics/manga/${mangaId}`)
        let st = res.statistics ? res.statistics[mangaId] : null
        let c = st ? st.comments : null
        if (!c || !c.threadId) return null
        let info = { threadId: c.threadId, replies: c.repliesCount || 0 }
        this._threads[mangaId] = info
        return info
    }

    decodeEntities(s) {
        return s.replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
            .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
            .replace(/&nbsp;/g, " ").replace(/&quot;/g, "\"").replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    }

    // 帖子 HTML 转纯文本：引用块折叠，换行保留
    forumText(html) {
        let s = html
        let prev = null
        while (prev !== s) {
            prev = s
            s = s.replace(/<blockquote(?:(?!<blockquote)[\s\S])*?<\/blockquote>/i, "〔引用〕\n")
        }
        s = s.replace(/<br\s*\/?>/gi, "\n")
            .replace(/<\/(p|div|li)>/gi, "\n")
            .replace(/<img[^>]*\balt="([^"]*)"[^>]*>/gi, "$1")
            .replace(/<[^>]+>/g, "")
        return this.decodeEntities(s).replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim()
    }

    parseForumPosts(html) {
        let list = []
        for (let b of html.split(/<article class="message message--post/).slice(1)) {
            let pick = (re) => { let m = b.match(re); return m ? m[1] : null }
            let id = pick(/data-content="post-(\d+)"/)
            if (!id) continue
            let avatar = pick(/class="avatar[^"]*"[^>]*>\s*<img[^>]*\bsrc="([^"]+)"/)
            if (avatar && avatar.startsWith("/")) avatar = this.forum + avatar
            let time = pick(/<time[^>]*\bdatetime="([^"]+)"/)
            let body = pick(/<div class="bbWrapper">([\s\S]*?)<div class="js-selectToQuoteEnd"/)
            list.push({
                userName: this.decodeEntities(pick(/data-author="([^"]*)"/) || "匿名"),
                avatar: avatar,
                content: body ? this.forumText(body.replace(/<\/div>\s*$/, "")) : "",
                time: time ? time.slice(0, 16).replace("T", " ") + " UTC" : null,
                replyCount: null,
                id: id,
            })
        }
        return list
    }


    async previewImages(comicId, chapters) {
        if (!chapters || chapters.size !== 1) return null
        let first = null
        for (let k of chapters.keys()) { first = k; break }
        if (!first) return null
        try {
            let images = await this.previewFromAtHome(first)
            return images && images.length ? images.slice(0, 20) : null
        } catch (e) {
            return null
        }
    }

    async previewFromAtHome(chapterId) {
        let res = await this.getJson(`/at-home/server/${chapterId}`)
        let files = res.chapter ? res.chapter.dataSaver : null
        if (!files) return null
        return files.map(f => `${res.baseUrl}/data-saver/${res.chapter.hash}/${f}`)
    }

    comic = {
        loadInfo: async (id) => {
            let res = await this.getJson(`/manga/${id}`, { includes: ["cover_art", "author", "artist"] })
            let m = res.data
            let a = m.attributes
            let tags = {}
            let authors = this.namesOf(m, "author")
            let artists = this.namesOf(m, "artist").filter(e => !authors.includes(e))
            if (authors.length) tags["作者"] = authors
            if (artists.length) tags["画师"] = artists
            let status = this.statusText(a.status)
            if (status) tags["状态"] = [status]
            if (a.year) tags["年份"] = [String(a.year)]
            if (a.contentRating) tags["分级"] = [a.contentRating]
            let chapters = await this.loadChapters(id)
            let genre = (a.tags || []).map(t => t.attributes.name.en)
            if (genre.length) tags["标签"] = genre
            if (a.originalLanguage) tags["原语言"] = [a.originalLanguage]
            return {
                title: this.pickTitle(a),
                cover: this.coverOf(m, 512),
                description: this.pickText(a.description),
                tags: tags,
                chapters: chapters,
                thumbnails: await this.previewImages(id, chapters),
            }
        },

        loadEp: async (comicId, epId) => {
            let res = await this.getJson(`/at-home/server/${epId}`)
            if (!res.chapter) throw "该章节暂不可用"
            let quality = this.setting("image_quality", "data")
            let files = quality === "data-saver" ? res.chapter.dataSaver : res.chapter.data
            if (!files || files.length === 0) throw "该章节没有可用图片（可能是外部链接章节）"
            return {
                images: files.map(f => `${res.baseUrl}/${quality}/${res.chapter.hash}/${f}`)
            }
        },

        onImageLoad: (url, comicId, epId) => {
            return { headers: this.headers }
        },

        // 评论：最新回复排在前面（论坛每页 20 楼）
        loadComments: async (comicId, subId, page, replyTo) => {
            let info = await this.threadInfo(comicId)
            if (!info) return { comments: [], maxPage: 1 }
            let maxPage = Math.max(1, Math.ceil((info.replies + 1) / 20))
            if (page > maxPage) return { comments: [], maxPage: maxPage }
            let res = await Network.get(`${this.forum}/threads/${info.threadId}/page-${maxPage - page + 1}`, this.forumHeaders)
            if (res.status !== 200) throw "评论加载失败：" + res.status
            let posts = this.parseForumPosts(res.body)
            posts.reverse()
            return { comments: posts, maxPage: maxPage }
        },

        onThumbnailLoad: (url) => {
            return { headers: this.headers }
        },
    }
}
