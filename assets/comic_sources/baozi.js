class Baozi extends ComicSource {
    // 包子漫画 —— PicaComic_MIUIX 内置源
    // 基于 wgh136/pica_configs (MIT, Copyright (c) 2024 wgh136) 的 baozi.js 修改：
    // 主站 baozimh.com 已启用人机验证，默认使用镜像域名（可在设置中切换）。
    // 此漫画源的名称
    name = "包子漫画"

    // 唯一标识符
    key = "baozi"

    version = "1.4.4"

    minAppVersion = "4.0.0"

    // 更新链接
    url = "https://raw.githubusercontent.com/Qilaiwing/PicaComic_miuix/miuix/assets/comic_sources/baozi.js"

    /// APP启动时或者添加/更新漫画源时执行此函数
    init() {}

    // 设置项（在 设置 - 漫画源 中显示）
    settings = {
language: {
            title: "简繁切换",
            type: "select",
            options: [
                { value: "cn", text: "简体" },
                { value: "tw", text: "繁體" },
            ],
            default: "cn",
        },
        domains: {
            title: "主域名",
            type: "select",
            options: [
                { value: "twmanga.com" },
                { value: "webmota.com" },
                { value: "dinnerku.com" },
                { value: "kukuc.co" },
                { value: "bzmgcn.com" },
                { value: "baozimhcn.com" },
            ],
            default: "twmanga.com",
        },
        cdn_domains: {
            title: "图片资源站域名",
            type: "select",
            options: [
                { value: "", text: "默认" },
                { value: "s1.baozicdn.com" },
                { value: "as.baozimh.com" },
                { value: "as-rsa1-usla.baozicdn.com" },
                { value: "ascn-a3.bzcdn.net" },
                { value: "asgb-a3.bzcdn.net" },
            ],
            default: "",
        },
        image_quality: {
            title: "图片质量",
            type: "select",
            options: [
                { value: "/w640", text: "640p" },
                { value: "", text: "原图" },
            ],
            default: "/w640",
        },
    }

    get lang() {
        return this.loadSetting("language") || "cn"
    }

    get domain() {
        // 兼容 1.2.0 的 "domain" 设置
        let saved = this.loadData("settings") || {}
        return saved.domains || saved.domain || "twmanga.com"
    }

    get baseUrl(){
        return `https://${this.lang}.${this.domain}`
    }

    // 账号：网页端 /api/bui/signin，返回的 token 写入 TSID cookie
    account = {
        login: async (account, pwd) => {
            let boundary = "----PicaBaoziForm" + Date.now().toString(16)
            let field = (k, v) => `--${boundary}\r\nContent-Disposition: form-data; name="${k}"\r\n\r\n${v}\r\n`
            let body = field("username", account) + field("password", pwd) + `--${boundary}--\r\n`
            let res = await Network.post(`${this.baseUrl}/api/bui/signin`, {
                "content-type": `multipart/form-data; boundary=${boundary}`,
            }, body)
            let json = null
            try { json = JSON.parse(res.body) } catch (e) {}
            if (res.status !== 200 || !json) throw "Invalid status code: " + res.status
            if (!json.data) {
                const msg = { ERR_MAIL: "账号不存在", ERR_SIGNIN_NAME_OR_PASSWORD: "账号或密码错误", ERR_PASSWORD: "密码错误", ERR_PASS: "密码错误" }
                throw msg[json.code] ?? (json.message || json.code || "登录失败")
            }
            Network.setCookies(this.baseUrl, [
                new Cookie("TSID", json.data, "." + this.domain),
            ])
            this.saveData("username", account)
            return "ok"
        },
        logout: () => {
            Network.deleteCookies(this.baseUrl)
            this.deleteData("username")
        },
        registerWebsite: null,
        // 校验登录状态：书架页能正常打开即有效
        checkStatus: async () => {
            let res = await Network.get(`${this.baseUrl}/user/my_bookshelf`)
            let ok = res.status === 200 && !/\/user\/login|signin/.test(res.body.slice(0, 3000)) && res.body.includes("bookshelf")
            return { valid: ok, username: this.loadData("username") }
        },
    }

    parseComic(e) {
        let url = e.querySelector("a").attributes['href']
        let id = url.split("/").pop()
        let title = e.querySelector("h3").text.trim()
        let cover = e.querySelector("a > amp-img").attributes["src"]
        let tags = e.querySelectorAll("div.tabs > span").map(e => e.text.trim())
        let description = e.querySelector("small").text.trim()
        return {
            id: id,
            title: title,
            cover: cover,
            tags: tags,
            description: description
        }
    }

    parseJsonComic(e) {
        return {
            id: e.comic_id,
            title: e.name,
            subTitle: e.author,
            cover: `https://static-tw.baozimh.com/cover/${e.topic_img}?w=285&h=375&q=100`,
            tags: e.type_names,
        }
    }

    /// 探索页面
    /// 一个漫画源可以有多个探索页面
    explore = [
        {
            /// 标题
            /// 标题同时用作标识符, 不能重复
            title: "包子漫画",

            /// singlePageWithMultiPart 或者 multiPageComicList
            type: "singlePageWithMultiPart",

            load: async () => {
                var res = await Network.get(this.baseUrl)
                if (res.status !== 200) {
                    throw "Invalid status code: " + res.status
                }
                let document = new HtmlDocument(res.body)
                let parts = document.querySelectorAll("div.index-recommend-items")
                let result = {}
                for (let part of parts) {
                    let title = part.querySelector("div.catalog-title").text.trim()
                    let comics = part.querySelectorAll("div.comics-card").map(e => this.parseComic(e))
                    if(comics.length > 0) {
                        result[title] = comics
                    }
                }
                return result
            }
        }
    ]

    /// 分类页面
    /// 一个漫画源只能有一个分类页面, 也可以没有, 设置为null禁用分类页面
    category = {
        /// 标题, 同时为标识符, 不能与其他漫画源的分类页面重复
        title: "包子漫画",
        parts: [
            {
                name: "类型",

                // fixed 或者 random
                // random用于分类数量相当多时, 随机显示其中一部分
                type: "fixed",

                // 如果类型为random, 需要提供此字段, 表示同时显示的数量
                // randomNumber: 5,

                categories: ['全部', '恋爱', '纯爱', '古风', '异能', '悬疑', '剧情', '科幻', '奇幻', '玄幻', '穿越', '冒险', '推理', '武侠', '格斗', '战争', '热血', '搞笑', '大女主', '都市', '总裁', '后宫', '日常', '韩漫', '少年', '其它'],

                // category或者search
                // 如果为category, 点击后将进入分类漫画页面, 使用下方的`categoryComics`加载漫画
                // 如果为search, 将进入搜索页面
                itemType: "category",

                // 若提供, 数量需要和`categories`一致, `categoryComics.load`方法将会收到此参数
                categoryParams: ['all', 'lianai', 'chunai', 'gufeng', 'yineng', 'xuanyi', 'juqing', 'kehuan', 'qihuan', 'xuanhuan', 'chuanyue', 'mouxian', 'tuili', 'wuxia', 'gedou', 'zhanzheng', 'rexie', 'gaoxiao', 'danuzhu', 'dushi', 'zongcai', 'hougong', 'richang', 'hanman', 'shaonian', 'qita']
            }
        ],
        enableRankingPage: false,
    }

    /// 分类漫画页面, 即点击分类标签后进入的页面
    categoryComics = {
        load: async (category, param, options, page) => {
            let res = await Network.get(`${this.baseUrl}/api/bzmhq/amp_comic_list?type=${param}&region=${options[0]}&state=${options[1]}&filter=%2a&page=${page}&limit=36&language=${this.lang}&__amp_source_origin=https%3A%2F%2F${this.lang}.${this.domain}`)
            if (res.status !== 200) {
                throw "Invalid status code: " + res.status
            }
            let maxPage = null
            let json = JSON.parse(res.body)
            if(!json.next) {
                maxPage = page
            }
            return {
                comics: json.items.map(e => this.parseJsonComic(e)),
                maxPage: maxPage
            }
        },
        // 提供选项
        optionList: [
            {
                options: [
                    "all-全部",
                    "cn-国漫",
                    "jp-日本",
                    "kr-韩国",
                    "en-欧美",
                ],
            },
            {
                options: [
                    "all-全部",
                    "serial-连载中",
                    "pub-已完结",
                ],
            },
        ],
    }

    /// 搜索
    search = {
        load: async (keyword, options, page) => {
            let res = await Network.get(`${this.baseUrl}/search?q=${keyword}`)
            if (res.status !== 200) {
                throw "Invalid status code: " + res.status
            }
            let document = new HtmlDocument(res.body)
            let comics = document.querySelectorAll("div.comics-card").map(e => this.parseComic(e))
            return {
                comics: comics,
                maxPage: 1
            }
        },

        // 提供选项
        optionList: []
    }

    /// 收藏
    favorites = {
        /// 是否为多收藏夹
        multiFolder: false,
        /// 添加或者删除收藏
        addOrDelFavorite: async (comicId, folderId, isAdding) => {
            if(!isAdding) {
                let res = await Network.post(`${this.baseUrl}/user/operation_v2?op=del_bookmark&comic_id=${comicId}`)
                if (!res.status || res.status >= 400) {
                    throw "Invalid status code: " + res.status
                }
                return 'ok'
            } else {
                let res = await Network.post(`${this.baseUrl}/user/operation_v2?op=set_bookmark&comic_id=${comicId}&chapter_slot=0`)
                if (!res.status || res.status >= 400) {
                    throw "Invalid status code: " + res.status
                }
                return 'ok'
            }
        },
        // 加载收藏夹, 仅当multiFolder为true时有效
        // 当comicId不为null时, 需要同时返回包含该漫画的收藏夹
        loadFolders: null,
        /// 加载漫画
        loadComics: async (page, folder) => {
            let res = await Network.get(`${this.baseUrl}/user/my_bookshelf`)
            if (res.status !== 200) {
                throw "Invalid status code: " + res.status
            }
            let document = new HtmlDocument(res.body)
            function parseComic(e) {
                let title = e.querySelector("h4 > a").text.trim()
                let url = e.querySelector("h4 > a").attributes['href']
                let id = url.split("/").pop()
                let author = e.querySelector("div.info > ul").children[1].text.split("：")[1].trim()
                let description = e.querySelector("div.info > ul").children[4].children[0].text.trim()

                return {
                    id: id,
                    title: title,
                    subTitle: author,
                    description: description,
                    cover: e.querySelector("amp-img").attributes['src']
                }
            }
            let comics = document.querySelectorAll("div.bookshelf-items").map(e => parseComic(e))
            return {
                comics: comics,
                maxPage: 1
            }
        }
    }

    /// 单个漫画相关

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
                lastError = e
                await new Promise(r => setTimeout(r, 500 * (i + 1)))
            }
        }
        throw lastError
    }

    comic = {
        // 加载漫画信息
        loadInfo: async (id) => {
            let res = await Network.get(`${this.baseUrl}/comic/${id}`)
            if (res.status !== 200) {
                throw "Invalid status code: " + res.status
            }
            let document = new HtmlDocument(res.body)

            let title = document.querySelector("h1.comics-detail__title").text.trim()
            let cover = document.querySelector("div.l-content > div > div > amp-img").attributes['src']
            let author = document.querySelector("h2.comics-detail__author").text.trim()
            let tags = document.querySelectorAll("div.tag-list > span").map(e => e.text.trim()).filter(e => e.length > 0)
            let updateTime = document.querySelector("div.supporting-text > div > span > em").text.trim().replace('(', '').replace(')', '')
            let description = document.querySelector("p.comics-detail__desc").text.trim()
            let chapters = new Map()
            let anchors = document.querySelectorAll("div#chapter-items > div.comics-chapters > a, div#chapters_other_list > div.comics-chapters > a")
            if (anchors.length === 0) {
                anchors = document.querySelectorAll("div.comics-chapters > a")
            }
            for (let a of anchors) {
                let href = a.attributes['href'] ?? ""
                let s = href.match(/section_slot=(\d+)/)
                let c = href.match(/chapter_slot=(\d+)/)
                if (!s || !c) continue
                chapters.set(`${s[1]}_${c[1]}`, a.text.trim())
            }
            let recommend = []
            for(let c of document.querySelectorAll("div.recommend--item")) {
                if(c.querySelectorAll("div.tag-comic").length > 0) {
                    let title = c.querySelector("span").text.trim()
                    let cover = c.querySelector("amp-img").attributes['src']
                    let url = c.querySelector("a").attributes['href']
                    let id = url.split("/").pop()
                    recommend.push({
                        id: id,
                        title: title,
                        cover: cover
                    })
                }
            }

            return {
                title: title,
                cover: cover,
                description: description,
                tags: {
                    "作者": [author],
                    "更新": [updateTime],
                    "标签": tags
                },
                chapters: chapters,
                thumbnails: await this.previewImages(id, chapters),
                recommend: recommend
            }
        },
        // 获取章节图片
        loadEp: async (comicId, epId) => this.loadEpWithRetry(comicId, epId),
        _loadEpOnce: async (comicId, epId) => {
            let ep = epId.includes('_') ? epId : '0_' + epId
            let images = []
            let res = await Network.get(`${this.baseUrl}/comic/chapter/${comicId}/${ep}.html`)
            if (res.status === 200) {
                let document = new HtmlDocument(res.body)
                let all = document.querySelectorAll("ul.comic-contain > div > amp-img").map(e => e.attributes['src'])
                // 最新章节在网页端会用其他漫画的占位图代替，这里过滤掉
                let idMatch = res.body.match(/comic_id=([a-z0-9_-]+)/)
                let slug = idMatch ? idMatch[1] : comicId.replace(/_[a-z0-9]{6}$/, "")
                images = [...new Set(all)].filter(e => e && e.includes(`/${slug}/`))
            }
            if (images.length === 0) {
                // 网页端无图时尝试 App 版页面（海外网络可用）
                try {
                    let app = await Network.get(`https://app${this.lang}.baozimh.com/baozimhapp/comic/chapter/${comicId}/${ep}.html`)
                    if (app.status === 200) {
                        let doc = new HtmlDocument(app.body)
                        images = doc.querySelectorAll(".comic-contain .comic-contain__item")
                            .map(e => e.attributes['data-src']).filter(e => e)
                    }
                } catch (e) {}
            }
            if (images.length === 0) {
                throw res.status === 200 ? "该章节网页端暂未开放" : "Invalid status code: " + res.status
            }
            return { images: images.map(u => this.rewriteImage(u)) }
        },
    }

    // 按设置替换图片域名与质量
    rewriteImage(url) {
        let m = url.match(/^(https?:\/\/)([^/]+)(\/w\d+)?(\/[a-z]comic\/.*)$/)
        if (!m) return url
        let host = this.loadSetting("cdn_domains") || m[2]
        let q = this.loadSetting("image_quality") ?? "/w640"
        return `${m[1]}${host}${q}${m[4]}`
    }
}
