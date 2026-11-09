class ManHuaGui extends ComicSource {
    // 漫画柜 —— PicaComic_MIUIX 内置源（独立编写）
    name = "漫画柜"

    key = "manhuagui"

    version = "1.2.4"

    minAppVersion = "4.0.0"

    url = "https://raw.githubusercontent.com/Qilaiwing/PicaComic_miuix/miuix/assets/comic_sources/manhuagui.js"

    // 设置项（在 设置 - 漫画源 中显示）
    settings = {
        domain: {
            title: "站点",
            type: "select",
            options: [
                { value: "www.manhuagui.com", text: "简体 (www)" },
                { value: "tw.manhuagui.com", text: "繁體 (tw)" },
            ],
            default: "www.manhuagui.com",
        },
        image_server: {
            title: "图片线路",
            type: "select",
            options: [
                { value: "i", text: "自动" },
                { value: "us", text: "美国" },
                { value: "eu", text: "欧洲" },
                { value: "us1", text: "美国 1" },
                { value: "us2", text: "美国 2" },
                { value: "us3", text: "美国 3" },
            ],
            default: "i",
        },
show_group: {
            title: "章节名显示分组",
            type: "switch",
            default: true,
        },
    }

    get baseUrl() {
        return "https://" + (this.loadSetting("domain") || "www.manhuagui.com")
    }

    get headers() {
        return {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Referer": this.baseUrl + "/",
        }
    }

    init() {}

    async getHtml(url) {
        let lastError = null
        for (let i = 0; i < 3; i++) {
            try {
                let res = await Network.get(url, this.headers)
                if (res.status === 200) {
                    return res.body
                }
                lastError = "Invalid status code: " + res.status
            } catch (e) {
                lastError = e
            }
            if (i < 2) await new Promise(r => setTimeout(r, 400 * (i + 1)))
        }
        throw lastError
    }

    fixUrl(url) {
        if (!url) return url
        if (url.startsWith("//")) return "https:" + url
        if (url.startsWith("/")) return this.baseUrl + url
        return url
    }

    idFromHref(href) {
        let m = /\/comic\/(\d+)/.exec(href || "")
        return m ? m[1] : null
    }

    parseMaxPage(document) {
        let strong = document.querySelectorAll("div.result-count > strong")
        if (strong.length >= 2) {
            let n = parseInt(strong[1].text.trim())
            if (!isNaN(n)) return n
        }
        return 1
    }

    // 列表页 / 分类页
    parseListPage(html) {
        let document = new HtmlDocument(html)
        let comics = []
        for (let li of document.querySelectorAll("#contList > li")) {
            let a = li.querySelector("a.bcover")
            if (!a) continue
            let id = this.idFromHref(a.attributes["href"])
            if (!id) continue
            let img = a.querySelector("img")
            let cover = img ? (img.attributes["data-src"] || img.attributes["src"]) : null
            let tt = a.querySelector("span.tt")
            comics.push({
                id: id,
                title: a.attributes["title"] || "",
                cover: this.fixUrl(cover),
                subTitle: tt ? tt.text.trim() : "",
                tags: [],
                description: "",
            })
        }
        let maxPage = this.parseMaxPage(document)
        return { comics: comics, maxPage: maxPage }
    }

    parseSearchPage(html) {
        let document = new HtmlDocument(html)
        let comics = []
        for (let li of document.querySelectorAll("div.book-result li.cf")) {
            let a = li.querySelector("a.bcover")
            if (!a) continue
            let id = this.idFromHref(a.attributes["href"])
            if (!id) continue
            let img = a.querySelector("img")
            let cover = img ? (img.attributes["data-src"] || img.attributes["src"]) : null
            let status = li.querySelector("dd.status")
            let tags = li.querySelectorAll("dd.tags a").map(e => e.text.trim()).filter(e => e && !e.startsWith("第"))
            comics.push({
                id: id,
                title: a.attributes["title"] || "",
                cover: this.fixUrl(cover),
                subTitle: tags.slice(0, 2).join(" "),
                tags: tags,
                description: status ? status.text.trim() : "",
            })
        }
        let maxPage = this.parseMaxPage(document)
        return { comics: comics, maxPage: maxPage }
    }

    listUrl(path, page) {
        // path 形如 "list/" 或 "list/japan/"，排序为 update / view
        return page > 1 ? `${this.baseUrl}/${path}_p${page}.html` : `${this.baseUrl}/${path}.html`
    }

    explore = [
        {
            title: "漫画柜 最新更新",
            type: "multiPageComicList",
            load: async (page) => {
                return this.parseListPage(await this.getHtml(this.listUrl("list/update", page)))
            }
        },
        {
            title: "漫画柜 人气最旺",
            type: "multiPageComicList",
            load: async (page) => {
                return this.parseListPage(await this.getHtml(this.listUrl("list/view", page)))
            }
        },
    ]

    category = {
        title: "漫画柜",
        parts: [
            {
                name: "剧情",
                type: "fixed",
                categories: ["热血", "冒险", "魔幻", "神鬼", "搞笑", "萌系", "爱情", "科幻", "魔法", "格斗", "武侠", "机战", "战争", "竞技", "体育", "校园", "生活", "励志", "历史", "伪娘", "宅男", "腐女", "耽美", "百合", "后宫", "治愈", "美食", "推理", "悬疑", "恐怖", "四格", "职场", "侦探", "社会", "音乐", "舞蹈", "杂志", "黑道"],
                itemType: "category",
                categoryParams: ["rexue", "maoxian", "mohuan", "shengui", "gaoxiao", "mengxi", "aiqing", "kehuan", "mofa", "gedou", "wuxia", "jizhan", "zhanzheng", "jingji", "tiyu", "xiaoyuan", "shenghuo", "lizhi", "lishi", "weiniang", "zhainan", "funv", "danmei", "baihe", "hougong", "zhiyu", "meishi", "tuili", "xuanyi", "kongbu", "sige", "zhichang", "zhentan", "shehui", "yinyue", "wudao", "zazhi", "heidao"],
            },
            {
                name: "地区",
                type: "fixed",
                categories: ["日本", "港台", "其它", "欧美", "内地", "韩国"],
                itemType: "category",
                categoryParams: ["japan", "hongkong", "other", "europe", "china", "korea"],
            },
        ],
        enableRankingPage: false,
    }

    categoryComics = {
        load: async (category, param, options, page) => {
            let order = options[0] || "update"
            return this.parseListPage(await this.getHtml(this.listUrl(`list/${param}/${order}`, page)))
        },
        optionList: [
            {
                options: ["update-最新更新", "view-人气最旺", "rate-评分最高", "index-最新发布"],
            }
        ],
    }

    search = {
        load: async (keyword, options, page) => {
            let kw = encodeURIComponent(keyword)
            let url = page > 1 ? `${this.baseUrl}/s/${kw}_p${page}.html` : `${this.baseUrl}/s/${kw}.html`
            return this.parseSearchPage(await this.getHtml(url))
        },
        optionList: [],
    }

    favorites = null


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

    comic = {
        loadInfo: async (id) => {
            let html = await this.getHtml(`${this.baseUrl}/comic/${id}/`)
            let document = new HtmlDocument(html)
            let title = document.querySelector("div.book-title > h1").text.trim()
            let coverImg = document.querySelector("p.hcover > img")
            let cover = coverImg ? this.fixUrl(coverImg.attributes["src"]) : ""
            let introEl = document.querySelector("#intro-all") || document.querySelector("#intro-cut")
            let description = introEl ? introEl.text.trim() : ""

            let tags = {}
            for (let span of document.querySelectorAll("ul.detail-list > li > span")) {
                let strong = span.querySelector("strong")
                if (!strong) continue
                let label = strong.text.replace("：", "").replace(":", "").trim()
                let values = span.querySelectorAll("a").map(e => e.text.trim()).filter(e => e)
                if (label === "漫画状态") {
                    let s = span.querySelector("span")
                    if (s) values = [s.text.trim()]
                }
                if (label === "漫画别名" && values.length === 0) continue
                if (values.length === 0) continue
                let name = {"出品年代": "年代", "漫画地区": "地区", "字母索引": null, "漫画剧情": "剧情", "漫画作者": "作者", "漫画别名": "别名", "漫画状态": "状态"}[label]
                if (name === null) continue
                tags[name || label] = values
            }
            let statusLi = document.querySelector("ul.detail-list > li.status")
            if (statusLi) {
                let reds = statusLi.querySelectorAll("span.red")
                if (reds.length > 0) tags["状态"] = [reds[0].text.trim()]
                if (reds.length > 1) tags["更新"] = [reds[1].text.trim()]
            }

            // 部分漫画（如限制级）的章节列表被压缩后放在 __VIEWSTATE 中
            let chapterDoc = document
            let viewState = document.querySelector("#__VIEWSTATE")
            if (viewState && viewState.attributes["value"]) {
                let decoded = MhgLZ.decompressFromBase64(viewState.attributes["value"])
                if (decoded) chapterDoc = new HtmlDocument(`<div>${decoded}</div>`)
            }

            let chapters = new Map()
            let headings = chapterDoc.querySelectorAll("h4 > span").map(e => e.text.trim())
            let lists = chapterDoc.querySelectorAll("div.chapter-list")
            let multi = lists.length > 1
            lists.forEach((list, index) => {
                let prefix = this.loadSetting("show_group") !== false && multi && headings[index] && !["单话", "單話"].includes(headings[index]) ? `[${headings[index]}] ` : ""
                for (let ul of list.querySelectorAll("ul")) {
                    // 每个 ul 内为倒序排列，ul 之间为正序
                    let items = ul.querySelectorAll("li > a")
                    items.reverse()
                    for (let a of items) {
                        let m = /\/comic\/\d+\/(\d+)\.html/.exec(a.attributes["href"] || "")
                        if (!m) continue
                        chapters.set(m[1], prefix + (a.attributes["title"] || a.text.trim()))
                    }
                }
            })

            return {
                title: title,
                cover: cover,
                description: description,
                tags: tags,
                chapters: chapters,
                thumbnails: await this.previewImages(id, chapters),
            }
        },

        loadEp: async (comicId, epId) => {
            let html = await this.getHtml(`${this.baseUrl}/comic/${comicId}/${epId}.html`)
            let data = MhgUnpack.parseChapter(html)
            if (!data || !data.files || data.files.length === 0) {
                throw "该章节暂不可用"
            }
            let host = `https://${this.loadSetting("image_server") || "i"}.hamreus.com`
            let query = data.sl ? `?e=${data.sl.e}&m=${data.sl.m}` : ""
            return {
                images: data.files.map(f => host + encodeURI(data.path + f) + query)
            }
        },

        // 评论（只读）：同一条可能带有被回复的上级
        loadComments: async (comicId, subId, page, replyTo) => {
            let res = await Network.get(`${this.baseUrl}/tools/submit_ajax.ashx?action=comment_list&book_id=${comicId}&page_index=${page}`,
                Object.assign({}, this.headers, { "Referer": `${this.baseUrl}/comic/${comicId}/` }))
            if (res.status !== 200) throw "评论加载失败：" + res.status
            let data = JSON.parse(res.body)
            let all = data.comments || {}
            let comments = []
            for (let chain of data.commentIds || []) {
                let ids = String(chain).split(",")
                let c = all[ids[0]]
                if (!c) continue
                let content = c.content || ""
                let parent = ids.length > 1 ? all[ids[1]] : null
                if (parent) content = `回复 ${parent.user_name || "匿名"}：${content}`
                comments.push({
                    userName: c.user_name || "匿名",
                    avatar: c.avatar && String(c.avatar).startsWith("http") ? c.avatar : null,
                    content: content,
                    time: c.add_time || null,
                    replyCount: null,
                    id: String(c.id),
                })
            }
            return { comments: comments, maxPage: Math.max(1, Math.ceil((data.total || 0) / 30)) }
        },

        onThumbnailLoad: (url) => {
            return {
                headers: {
                    "Referer": this.baseUrl + "/",
                    "User-Agent": this.headers["User-Agent"],
                }
            }
        },

        onImageLoad: (url, comicId, epId) => {
            return {
                headers: {
                    "Referer": this.baseUrl + "/",
                    "User-Agent": this.headers["User-Agent"],
                }
            }
        },
    }
}

// 解析章节页中的 p,a,c,k,e,d 打包脚本（不使用 eval，按规则手动展开）
const MhgUnpack = {
    parseChapter(html) {
        let m = /\}\('(.*?)',(\d+),(\d+),'([A-Za-z0-9+\/=]+)'\[/s.exec(html)
        if (!m) return null
        let p = m[1].replace(/\\'/g, "'").replace(/\\\\/g, "\\")
        let a = parseInt(m[2])
        let c = parseInt(m[3])
        let k = MhgLZ.decompressFromBase64(m[4]).split("|")
        let encode = (n) => {
            return (n < a ? "" : encode(Math.floor(n / a))) + ((n = n % a) > 35 ? String.fromCharCode(n + 29) : n.toString(36))
        }
        let dict = {}
        while (c--) {
            let key = encode(c)
            dict[key] = k[c] || key
        }
        let code = p.replace(/\b\w+\b/g, (w) => dict.hasOwnProperty(w) ? dict[w] : w)
        let jm = /imgData\((\{.*\})\)/s.exec(code)
        if (!jm) return null
        return JSON.parse(jm[1])
    }
}

// LZ 压缩的 Base64 解压实现（按 LZ 算法规则独立编写）
const MhgLZ = {
    alphabet: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",

    decompressFromBase64(input) {
        if (input == null || input === "") return ""
        let map = {}
        for (let i = 0; i < this.alphabet.length; i++) map[this.alphabet[i]] = i
        let pos = 0
        let bitPos = 32
        let cur = map[input[0]]
        let readBits = (n) => {
            let result = 0
            for (let i = 0; i < n; i++) {
                let bit = (cur & bitPos) > 0 ? 1 : 0
                bitPos >>= 1
                if (bitPos === 0) {
                    bitPos = 32
                    pos++
                    cur = map[input[pos]]
                }
                result |= bit << i
            }
            return result
        }
        let dict = [0, 1, 2]
        let enlargeIn = 4
        let numBits = 3
        let entry
        let w
        let out = []
        let first = readBits(2)
        if (first === 2) return ""
        let ch = String.fromCharCode(readBits(first === 0 ? 8 : 16))
        dict[3] = ch
        w = ch
        out.push(ch)
        let dictSize = 4
        while (true) {
            if (pos > input.length) return ""
            let code = readBits(numBits)
            if (code === 0 || code === 1) {
                dict[dictSize++] = String.fromCharCode(readBits(code === 0 ? 8 : 16))
                code = dictSize - 1
                enlargeIn--
            } else if (code === 2) {
                return out.join("")
            }
            if (enlargeIn === 0) {
                enlargeIn = Math.pow(2, numBits)
                numBits++
            }
            if (dict[code]) {
                entry = dict[code]
            } else if (code === dictSize) {
                entry = w + w[0]
            } else {
                return null
            }
            out.push(entry)
            dict[dictSize++] = w + entry[0]
            enlargeIn--
            w = entry
            if (enlargeIn === 0) {
                enlargeIn = Math.pow(2, numBits)
                numBits++
            }
        }
    }
}
