import SwiftUI
import UIKit

private let replyCardSurface = Color(hex:0xfffdf7)
private let replyCardBorder = Color(hex:0xebe0d5)

extension ContentView {
    // MARK: - Conversation side panel
    func comments(_ chosen:NativeCamp,width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        let isOfficialExample = discussionStory?.id.hasPrefix("example-") == true
        return VStack(alignment:.leading,spacing:0){
            HStack(spacing:10){
                Button {closeComments()} label:{
                    Image(systemName:"chevron.left").font(.system(size:13,weight:.medium))
                        .foregroundColor(Color(hex:0x75666d)).frame(width:44,height:44)
                        .contentShape(Rectangle())
                }.accessibilityLabel(l("返回","Back"))
                Text(l("大家的建议","The conversation")).font(.system(size:19,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                Spacer(minLength:0)
            }.padding(.leading,14).padding(.trailing,20).padding(.top,top+20).padding(.bottom,keyboardHeight > 0 ? 72 : 115)
            HStack(spacing:8){campTab(.devil,chosen:chosen,count:devilCount);campTab(.angel,chosen:chosen,count:angelCount)}
                .padding(.horizontal,20).padding(.top,14).padding(.bottom,12)
            ScrollView {
                LazyVStack(spacing:10){
                    let answers=discussionStory?.answers.filter {$0.side==chosen.rawValue} ?? []
                    if answers.isEmpty {
                        Text(isOfficialExample ? l("官方示例仅供阅读","Official examples are read-only") : l("还没有建议，来做第一个吧 ✨","No responses yet. Start the conversation ✨")).font(.system(size:14)).foregroundColor(Color(hex:0xa09494)).padding(.vertical,35)
                    }
                    ForEach(answers){answer in commentCard(answer)}
                }.padding(.horizontal,20).padding(.top,10).padding(.bottom,18)
                    .id(chosen)
                    .transition(.asymmetric(insertion:.move(edge: chosen == .angel ? .trailing:.leading).combined(with:.opacity),removal:.opacity))
            }
            if !isOfficialExample {
            HStack(spacing:9){
                MusicComposer(text:$composer,height:$composerHeight,focused:$composerFocused,
                              draft:$composerMusic,camp:chosen,chinese:zh,prompt:l("说点什么…","Say something kind…"))
                Button {sendPreview(chosen)} label:{HStack(spacing:4){Text(l("发送","Send"));Text("↑")}.font(.system(size:15,weight:.bold)).foregroundColor(.white).padding(.horizontal,16).frame(minHeight:44).background(chosen.accent,in:RoundedRectangle(cornerRadius:16))}.buttonStyle(PressScale())
            }.padding(.horizontal,16).padding(.top,8).padding(.bottom,keyboardHeight > 0 ? 8 : bottom+10)
                .background(Color(hex:0xfffdfb)).overlay(Rectangle().fill(Color(hex:0xeee5e2)).frame(height:1),alignment:.top)
                .opacity(selectedReply == nil ? 1 : 0)
                .allowsHitTesting(selectedReply == nil)
                .accessibilityHidden(selectedReply != nil)
            }
        }.frame(width:width,height:max(1,height-keyboardHeight),alignment:.top)
            .frame(width:width,height:height,alignment:.top)
            .modifier(ConversationForeground(progress:campProgress, incoming:true))
            .background(chosen.background)
            .simultaneousGesture(DragGesture(minimumDistance:8,coordinateSpace:.global)
                .updating($returningFromComments) { _, active, _ in active = true }
                .onChanged { value in
                    guard !composerFocused, !settling, selectedReply == nil, (utility == nil || (detailStory != nil && utility != "report")) else { return }
                    if axis == nil {
                        axis = abs(value.translation.width) > abs(value.translation.height) ? .returnFromComments : .scrollComments
                    }
                    guard axis == .returnFromComments else { return }
                    let distance = max(0,value.translation.width * -chosen.sign)
                    campProgress = max(0,1-distance/max(1,width))
                }
                .onEnded { value in
                    if axis == .scrollComments { axis = nil; return }
                    guard axis == .returnFromComments, !settling else { return }
                    if value.translation.width * -chosen.sign > max(65,width*0.23) { closeComments() }
                    else { settleCamp(to: 1) }
                })
    }
    func campTab(_ value:NativeCamp,chosen:NativeCamp,count:Int)->some View {
        Button {
            guard value != chosen else { return }
            composerFocused = false
            composer = ""; composerMusic = nil
            withAnimation(transitionAnimation){camp=value}
        } label:{
            HStack(spacing:7){
                Circle().fill(Color(hex:value == .devil ? 0xc9827b:0x83adc3)).frame(width:7,height:7)
                Text(value == .devil ? l("恶魔","Devil"):l("天使","Angel"))
                Text("\(count)").font(.system(size:12,weight:.bold)).opacity(0.7)
            }.font(.system(size:13,weight:.bold))
                .foregroundColor(Color(hex:chosen==value ? (value == .devil ? 0x994d49:0x426d88):0x756a6b))
                .padding(.horizontal,16).padding(.vertical,10)
                .background(Color(hex:chosen==value ? (value == .devil ? 0xf8d5ce:0xd8eaf5):0xf4efed),in:Capsule())
        }.buttonStyle(PressScale())
    }
    func commentCard(_ answer:NativeAnswer)->some View {
        let sid = discussionID ?? ""
        let mine = sid.hasPrefix("local-")
        let isBest = best["\(sid)|\(answer.side)"] == answer.id
        let online = usesLiveFeed && !sid.hasPrefix("local-")
            && model.sourceStories.contains { $0.id == sid && $0.answers.contains { $0.id == answer.id } }
        let isLiked = online ? answer.liked == true : liked[answer.id] == true
        return VStack(alignment:.leading,spacing:0){
            HStack{
                Text(displayAuthor(answer)).font(.system(size:12,weight:.bold)).foregroundColor(Color(hex:0x9a8888))
                if answer.author.contains("AI") { Text("AI").font(.system(size:9,weight:.bold)).foregroundColor(Color(hex:0xa87336)).padding(.horizontal,5).padding(.vertical,2).background(Color(hex:0xf7ead6),in:Capsule()) }
                Spacer()
                if isBest { Text("✦ " + l("最佳","Best")).font(.system(size:11)).foregroundColor(Color(hex:0xa87336)) }
                if !isOwnReportTarget("answer",answer.id,in:discussionStory) {
                    Button {openReport("answer",answer.id)} label:{Text("⚑ "+l("举报","Report")).font(.system(size:11)).foregroundColor(Color(hex:0xb0a29d)).padding(.leading,8).frame(height:26)}.buttonStyle(.plain)
                }
            }
            answerText(answer.text,side:NativeCamp(rawValue:answer.side))
            HStack(spacing:8){
                Button {
                    guard requireLogin("like") else{return}
                    if online {
                        writeToServer("like",fields:["id":answer.id]) { _ in }
                        return
                    }
                    let next = !isLiked
                    if let story = discussionStory {
                        rememberExpiry(of: story)
                        var parents = localState.replyStory ?? [:]
                        parents[answer.id] = story.id
                        localState.replyStory = parents
                    }
                    liked[answer.id]=next;persistLocal()
                } label:{
                    HStack(spacing:5){Image(systemName:isLiked ? "heart.fill":"heart").font(.system(size:15,weight:.light))
                            .id(isLiked).transition(.scale(scale:0.82).combined(with:.opacity));Text("\(min(max(0,answer.likes),Int.max-1) + (!online && isLiked ? 1:0))").font(.system(size:12))}
                        .foregroundColor(isLiked ? Color(hex:0xb85657):Color(hex:0x897a7a)).padding(.horizontal,11).frame(height:38)
                        .background(Color(hex:isLiked ? 0xf9e6e2:0xf8f4f2),in:Capsule()).animation(reduceMotion || !motionOn ? nil : .easeInOut(duration:0.19),value:isLiked)
                }.buttonStyle(PressScale())
                if mine {
                    Button {guard requireLogin("best") else{return};if let story = discussionStory { rememberExpiry(of: story) };if isBest {best["\(sid)|\(answer.side)"]=nil}else{best["\(sid)|\(answer.side)"]=answer.id};persistLocal()} label:{
                        Text(isBest ? "✦ "+l("取消最佳","Remove best"):l("选为最佳","Choose best")).font(.system(size:12))
                            .foregroundColor(Color(hex:0xa87336)).padding(.horizontal,8).frame(height:38)
                    }.buttonStyle(PressScale())
                }
                Spacer(minLength:0)
                Button {openReply(answer)} label:{
                    Text(answer.replies.isEmpty ? l("回复","Reply") : l("回复","Reply")+" · "+String(answer.replies.count)).font(.system(size:12)).foregroundColor(Color(hex:0x897a7a)).padding(.horizontal,11).frame(height:38).background(Color(hex:0xf8f4f2),in:Capsule())
                }.buttonStyle(PressScale())
            }.padding(.top,12)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background {
                RoundedRectangle(cornerRadius:18).fill(replyCardSurface)
                    .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(replyCardBorder,lineWidth:1))
                    .shadow(color:Color(hex:0x806a68).opacity(0.06),radius:8,y:4)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key:CardFrames.self,
                                           value:[answer.id:proxy.frame(in:.named("card-stage"))])
                }
            }
            .contentShape(RoundedRectangle(cornerRadius:18))
            .onTapGesture {openReply(answer)}
            .accessibilityHidden(selectedReply?.id == answer.id)
    }
    private func displayAuthor(_ answer: NativeAnswer) -> String {
        let mine = answer.mine == true || localState.answerOwnership?.contains(answer.id) == true
        return mine ? auth.account?.nickname ?? answer.author : answer.author
    }

    private func displayAuthor(_ reply: NativeReply) -> String {
        let mine = reply.mine == true || reply.id.map { localState.replyOwnership?.contains($0) == true } == true
        return mine ? auth.account?.nickname ?? reply.author : reply.author
    }

    private func answerText(_ text: String,side: NativeCamp?) -> some View {
        let share = MusicDraft.display(text)
        return VStack(alignment:.leading,spacing:8) {
            if !share.body.isEmpty {
                Text(share.body)
                    .font(.system(size:14))
                    .lineSpacing(max(0,14*1.6-UIFont.systemFont(ofSize:14).lineHeight))
                    .fixedSize(horizontal:false,vertical:true)
            }
            if let link = share.link {
                Link(destination:link.url) {
                    MusicCardLabel(title:share.title ?? link.platform,
                                   subtitle:share.title == nil ? nil : [share.artist,link.platform].compactMap { $0 }.joined(separator:" · "),
                                   accent:side?.accent ?? H5Design.muted,showArrow:true)
                }.buttonStyle(PressScale())
                    .accessibilityHint(l("打开歌曲","Open track"))
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,12)
    }

    private func musicPayload(_ body: String,draft: MusicDraft?) -> String? {
        let text = body.trimmingCharacters(in:.whitespacesAndNewlines)
        if let draft, draft.showTitle && MusicDraft.clean(draft.title).isEmpty {
            toast(l("请填写歌曲名，或取消展示","Enter a track title or turn off title display"))
            return nil
        }
        let payload = draft?.appending(to:text) ?? text
        guard !payload.isEmpty, allowsSingleMusicLink(payload) else { return nil }
        guard payload.unicodeScalars.count <= 1000 else {
            toast(l("正文和音乐信息最多 1000 字","Text and music details must fit within 1,000 characters"))
            return nil
        }
        return payload
    }

    private func allowsSingleMusicLink(_ text: String) -> Bool {
        guard SharedMusicLink.links(in:text).count <= 1 else {
            toast(l("每条评论或回复只能分享一首歌","Share one track per comment or reply"))
            return false
        }
        return true
    }

    func closeComments(){
        guard !settling else { return }
        composerFocused = false
        settleCamp(to: 0)
    }
    func sendPreview(_ chosen:NativeCamp){
        guard let text = musicPayload(composer,draft:composerMusic), requireLogin("respond") else { return }
        guard camp == chosen, let story = discussionStory,
              story.created/1000+86400 > Date().timeIntervalSince1970 else { return }
        guard !story.id.hasPrefix("example-") else {
            toast(l("官方示例仅供阅读","Official examples are read-only"))
            return
        }
        if usesLiveFeed && !story.id.hasPrefix("local-") {
            let draft = composer, attachment = composerMusic
            writeToServer("answers",fields:["storyId":story.id,"side":chosen.rawValue,"text":text]) { _ in
                if discussionID == story.id, camp == chosen, composer == draft, composerMusic?.id == attachment?.id {
                    composer = ""; composerMusic = nil; composerFocused = false
                }
                toast(l("建议已发布","Response posted"))
            }
            return
        }
        let answer = NativeAnswer(id:UUID().uuidString,author:myName,side:chosen.rawValue,text:text,likes:0,replies:[])
        localState.myAnswers[story.id,default:[]].append(answer)
        localState.answerOwnership = (localState.answerOwnership ?? []).union([answer.id])
        rememberExpiry(of: story)
        composer = ""; composerMusic = nil; composerFocused = false
        rebuildVisibleStories()
        persistLocal()
        toast(l("建议已保存在本机","Response saved on this device"))
    }

    // MARK: - Utility sheets
    func utilityPage(_ page:String,width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->AnyView {
        switch page {
        case "profile": return AnyView(profilePage(width:width,height:height,top:top,bottom:bottom))
        case "blocked": return AnyView(blockedPage(width:width,height:height,top:top,bottom:bottom))
        case "write": return AnyView(writePage(width:width,height:height,top:top,bottom:bottom))
        case "more": return AnyView(morePage(width:width,height:height,top:top,bottom:bottom))
        case "help-privacy": return AnyView(helpPrivacyPage(width:width,height:height,bottom:bottom))
        case "report": return AnyView(reportPage(width:width,height:height,top:top,bottom:bottom))
        case "update": return AnyView(updatePage(width:width,height:height,top:top,bottom:bottom))
        default: return AnyView(libraryPage(page,width:width,height:height,top:top,bottom:bottom))
        }
    }
    func sheetHead(_ title:String,top:CGFloat,padBottom:CGFloat=4,companionSlot:Bool=false)->some View {
        HStack(spacing:10){
            Text(title).font(.system(size:19,weight:.bold)).foregroundColor(Color(hex:0x302b32))
            Spacer(minLength:0)
            if companionSlot { Color.clear.frame(width:52,height:1).allowsHitTesting(false).accessibilityHidden(true) }
            Button {closeUtility()} label:{Text("‹").font(.system(size:32,weight:.light)).foregroundColor(Color(hex:0x75666d)).frame(width:44,height:44)}.accessibilityLabel(l("关闭","Close"))
        }.padding(.horizontal,16).padding(.top,top+12).padding(.bottom,padBottom)
    }
    func writePage(width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        let count = writeText.count
        let sheetBottom = max(1,height-keyboardHeight)
        let sheetTop = H5Design.writeSheetTop(height:height,safeTop:top)
        let sheetH = max(1,sheetBottom-sheetTop)

        return VStack(spacing:0){
            sheetHead(l("说说你的烦恼","What's on your mind?"),top:0,padBottom:8,companionSlot:keyboardHeight>0)
            GeometryReader { available in
                let editorHeight = max(136,available.size.height-132)
                ScrollView {
                    VStack(alignment:.leading,spacing:0){
                        HStack{
                            HStack(spacing:5){Text("✦");Text(l("匿名发布","Anonymous"))}.font(.system(size:12,weight:.bold)).foregroundColor(Color(hex:0xa8737a)).padding(.horizontal,11).padding(.vertical,6).background(Color(hex:0xf7e6e0),in:Capsule())
                            Spacer()
                        }
                        GrowField(text:$writeText,height:.constant(editorHeight),focused:$writeFieldFocused,maxHeight:editorHeight,
                                  label:l("烦恼正文","Story text"),prompt:l("最近有什么让你纠结的事？","What's been on your mind lately?"))
                            .frame(height:editorHeight,alignment:.topLeading).background(Color(hex:0xf7f1ee),in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(Color(hex:0xf0e7e2),lineWidth:1)).padding(.top,10)
                        HStack{
                            Text(l("说你想说的","In your own words"))
                            Spacer()
                            Text("\(count) / 1500")
                        }.font(.system(size:12)).foregroundColor(Color(hex:0xa29490)).padding(.top,8)
                        HStack(alignment:.top,spacing:7){
                            Text("◷").font(.system(size:12))
                            Text(l("烦恼和公开讨论将在 24 小时后消失。其他人可以在到期前保存私密快照。","The public story and discussion disappear after 24 hours. Others can save a private snapshot before then."))
                        }.font(.system(size:12)).foregroundColor(Color(hex:0x8c7b72)).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color(hex:0xf8f2ec),in:RoundedRectangle(cornerRadius:13)).padding(.top,14)
                    }.padding(.horizontal,20).padding(.bottom,10)
                }
            }
            Button {publishStory()} label:{
                HStack(spacing:6){Text(l("匿名发布","Share anonymously"));Text("↗")}
                    .font(.system(size:15,weight:.bold)).foregroundColor(.white)
                    .frame(maxWidth:.infinity,minHeight:48)
                    .background(Color(hex:0xc8786d),in:RoundedRectangle(cornerRadius:15))
            }.buttonStyle(PressScale())
                .padding(.horizontal,20)
                .padding(.top,8)
                .padding(.bottom,keyboardHeight > 0 ? 8 : bottom+12)
        }.frame(width:width,height:sheetH,alignment:.top).background(Color(hex:0xfffbf9)).clipShape(TopRoundedShape(radius:26)).offset(y:sheetTop).frame(width:width,height:height,alignment:.top)
    }
    func publishStory(){
        let text=writeText.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else{toast(l("请先写点内容","Write something first"));return}
        guard text.count <= 1500 else { toast(l("最多输入 1500 字","Limit: 1,500 characters")); return }
        guard requireLogin("publish") else{return}
        if usesLiveFeed {
            let draft = writeText
            writeToServer("stories",fields:["language":language,"category":"other","text":text]) { result in
                if utility == "write", writeText == draft {
                    writeText = ""; writeFieldFocused = false
                    withAnimation(transitionAnimation) { utility = nil }
                }
                toast(result.pending == true ? l("已提交，审核后可见","Submitted for review") : l("烦恼已发布","Story posted"))
            }
            return
        }
        localState.localStories.insert(NativeStory(id:"local-\(UUID().uuidString)",text:text,created:Date().timeIntervalSince1970*1000,answers:[]),at:0)
        rebuildVisibleStories()
        model.index=0;writeText="";writeFieldFocused=false;persistLocal();withAnimation(transitionAnimation){utility=nil}
        toast(l("烦恼已保存在本机","Story saved on this device"))
    }
    func morePage(width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        let available = max(1,height-top-bottom-20)
        let rows = model.current == nil ? 1 : 4
        let bodyHeight = min(CGFloat(rows*56+max(0,rows-1)*8),max(1,available-66))
        return VStack(alignment:.leading,spacing:4){
            sheetHead(l("更多","More"),top:0,padBottom:4)
            ScrollView {
            VStack(spacing:8){
                if model.current != nil {
                    moreRow("♡ "+l("保存完整讨论","Save discussion")){saveSnapshot()}
                }
                if model.current?.id.hasPrefix("local-") == true {
                    moreRow("✎ "+l("补充进展","Add an update")){updateText="";openUtility("update")}
                }
                if let story = model.current, !story.id.hasPrefix("example-"), !isOwnReportTarget("story",story.id,in:story) {
                    moreRow("⚑ "+l("举报内容","Report content")){openReport("story",story.id)}
                }
                if let story = model.current, !story.id.hasPrefix("local-") {
                    moreRow("⊘ "+l("屏蔽这条","Hide story")){hideStory()}
                }
                Toggle(isOn:$motionOn){Text(l("角色动效","Companion motion")).font(.system(size:15)).foregroundColor(Color(hex:0x59484b))}.tint(Color(hex:0xc8786d)).padding(.horizontal,15).padding(.vertical,12).background(.white,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Color(hex:0xeee7e4),lineWidth:1))
            }.padding(.horizontal,20).padding(.vertical,4)
            }.frame(height:bodyHeight)
        }.padding(.bottom,bottom+12).frame(width:width).background(Color(hex:0xfffbf9))
            .clipShape(TopRoundedShape(radius:26)).frame(width:width,height:height,alignment:.bottom)
    }
    func moreRow(_ title:String,action:@escaping ()->Void)->some View {
        Button(action:action,label:{
            HStack{Text(title);Spacer()}.font(.system(size:15)).foregroundColor(Color(hex:0x59484b)).padding(15).frame(maxWidth:.infinity)
                .background(.white,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Color(hex:0xeee7e4),lineWidth:1))
        }).buttonStyle(PressScale())
    }
    func saveSnapshot(){
        guard let story = model.current, story.created/1000+86400 > Date().timeIntervalSince1970,
              requireLogin("save") else { return }
        if !snapshots.contains(where:{$0.id==story.id}) { snapshots.append(story) }
        persistLocal()
        withAnimation(transitionAnimation){utility=nil}
        toast(l("快照已保存","Snapshot saved"))
    }
    func hideStory(){
        guard model.stories.indices.contains(model.index) else{return}
        let story = model.stories[model.index]
        let id = story.id
        guard !id.hasPrefix("local-") else { return }
        rememberExpiry(of: story)
        if !hidden.contains(id) { hidden.append(id) }
        var t=Transaction();t.disablesAnimations=true
        withTransaction(t){ model.stories.remove(at:model.index); if model.index >= model.stories.count { model.index = max(0,model.stories.count-1) } }
        persistLocal()
        withAnimation(transitionAnimation){utility=nil}
        toast(l("已屏蔽这条烦恼","Story hidden"))
    }
    var reportReasons: [(String,String)] {
        [(l("骚扰或攻击","Harassment or abuse"),"harassment"),(l("仇恨或歧视","Hate or discrimination"),"hate"),(l("涉及人身安全","Safety concern"),"safety"),(l("泄露隐私","Privacy violation"),"privacy"),(l("垃圾信息或其他","Spam or other"),"spam")]
    }
    func reportPage(width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {

        return VStack(alignment:.leading,spacing:0){
            HStack(spacing:10){
                Button {closeReport()} label:{Text("‹").font(.system(size:32,weight:.light)).foregroundColor(Color(hex:0x75666d)).frame(width:44,height:44)}.accessibilityLabel(l("返回","Back"))
                Text(l("举报内容","Report content")).font(.system(size:19,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                Spacer()
            }.padding(.horizontal,16).padding(.top,top+12).padding(.bottom,10)
            Text(reportType=="answer" ? l("正在举报一条建议","Reporting a response") : reportType=="reply" ? l("正在举报一条回复","Reporting a reply") : l("正在举报这条烦恼","Reporting this story")).font(.system(size:11)).foregroundColor(Color(hex:0xa29490)).padding(.horizontal,20).padding(.bottom,10)
            VStack(spacing:10){
                ForEach(Array(reportReasons.enumerated()),id:\.offset){ _,reason in
                    Button {reportReason=reason.1} label:{
                        HStack{
                            Text(reason.0).font(.system(size:14)).foregroundColor(Color(hex:0x59484b))
                            Spacer()
                            Image(systemName:reportReason==reason.1 ? "largecircle.fill.circle":"circle").font(.system(size:17)).foregroundColor(Color(hex:reportReason==reason.1 ? 0xc8786d:0xc9b7b2))
                        }.padding(15).frame(maxWidth:.infinity).background(.white,in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(Color(hex:0xf0e7e2),lineWidth:1))
                    }
                }
                if reportUsesServer || reportAuthorID != nil {
                    Toggle(l("同时拉黑此人","Also block this person"),isOn:$reportAlsoBlock)
                        .font(.system(size:14)).tint(Color(hex:0xb76f73))
                }
                Button {confirmReport()} label:{
                    Text(l("确认举报","Confirm report")).font(.system(size:15,weight:.bold)).foregroundColor(.white).frame(maxWidth:.infinity,minHeight:46).background(Color(hex:0x443a43),in:RoundedRectangle(cornerRadius:14))
                }.padding(.top,4).disabled(serverWriteInFlight)
                Text(reportUsesServer ? l("举报将提交审核。","This report will be sent for review.")
                                      : l("这条举报会保存在本机。","This report is saved on this device.")).font(.system(size:12)).foregroundColor(Color(hex:0x8a7979)).lineSpacing(4)
            }.padding(.horizontal,20).padding(.bottom,bottom+20)
            Spacer(minLength:0)
        }.frame(width:width,height:height,alignment:.top).background(Color(hex:0xfffbf9))
    }
    private func isOwnReportTarget(_ type: String,_ id: String,in story: NativeStory?) -> Bool {
        switch type {
        case "story": return id.hasPrefix("local-") || story?.mine == true
        case "answer": return localState.answerOwnership?.contains(id) == true
            || story?.answers.first(where:{ $0.id == id })?.mine == true
        case "reply": return localState.replyOwnership?.contains(id) == true
            || story?.answers.lazy.flatMap(\.replies).first(where:{ $0.id == id })?.mine == true
        default: return true
        }
    }

    func openReport(_ type:String,_ id:String){
        guard let story = type == "story" ? model.current : discussionStory, !id.isEmpty,
              !isOwnReportTarget(type,id,in:story) else { return }
        composerFocused = false
        replyFocused = false
        reportStoryId = story.id
        reportReason = "harassment"
        reportFrom = utility
        reportType=type;reportId=id
        reportAlsoBlock = false
        switch type {
        case "story": reportAuthorID = story.authorID
        case "answer": reportAuthorID = story.answers.first { $0.id == id }?.authorID
        case "reply": reportAuthorID = story.answers.lazy.flatMap(\.replies).first { $0.id == id }?.authorID
        default: reportAuthorID = nil
        }
        let source = model.sourceStories.first { $0.id == story.id }
        reportUsesServer = usesLiveFeed && source.map { source in
            switch type {
            case "story": return source.id == id
            case "answer": return source.answers.contains { $0.id == id }
            case "reply": return source.answers.lazy.flatMap(\.replies).contains { $0.id == id }
            default: return false
            }
        } == true
        openUtility("report")
    }
    func closeReport(){
        let back=reportFrom
        reportFrom = nil
        reportStoryId = nil
        reportId = ""
        reportAuthorID = nil
        reportAlsoBlock = false
        reportUsesServer = false
        withAnimation(transitionAnimation) { utility = back }
    }

    private func recordReport(_ raw: String,details: NativeReportDetails) {
        if !reports.contains(raw) { reports.append(raw) }
        var records = localState.reportDetails ?? [:]
        records[raw] = details
        localState.reportDetails = records
    }

    private func recordBlock(_ record: NativeBlockedRecord) {
        var records = localState.blockedRecords ?? []
        if !records.contains(where:{ $0.id == record.id && $0.server == record.server }) { records.append(record) }
        localState.blockedRecords = records
        if !record.server {
            localState.blockedAuthorIDs = (localState.blockedAuthorIDs ?? []).union([record.id])
        }
    }

    func confirmReport(){
        guard !serverWriteInFlight else { return }
        guard let sid = reportStoryId,
              let story = model.stories.first(where:{ $0.id == sid && $0.created/1000+86400 > Date().timeIntervalSince1970 }) else {
            closeReport()
            toast(l("这条烦恼已不可用","This story is no longer available"))
            return
        }
        let type = reportType, id = reportId, reason = reportReason
        guard !isOwnReportTarget(type,id,in:story) else {
            closeReport()
            toast(l("不能举报自己的内容","You can’t report your own content"))
            return
        }
        guard requireLogin("report") else { return }
        let raw = [sid,type,id,reason].joined(separator:"|")
        var details = reportDetails(raw)
        if details.createdAt == nil { details.createdAt = Date() }
        let block = reportAlsoBlock
        if reportUsesServer {
            let viewer = serverViewer
            serverWriteInFlight = true
            Task {
                defer { serverWriteInFlight = false }
                do {
                    if details.acceptanceStatus == nil {
                        _ = try await model.mutate("report",fields:["id":id,"targetType":type,"value":reason],viewer:viewer)
                        guard serverViewer == viewer else { return }
                        details.acceptanceStatus = l("已提交，待审核","Submitted for review")
                        recordReport(raw,details:details)
                        persistLocal()
                    }
                    if block {
                        do {
                            let result = try await model.mutate("block-user",fields:["id":id,"targetType":type],viewer:viewer)
                            guard serverViewer == viewer else { return }
                            recordBlock(NativeBlockedRecord(id:result.id ?? "\(type):\(id)",nickname:details.targetNickname,blockedAt:Date(),server:true))
                            persistLocal()
                        } catch {
                            guard serverViewer == viewer else { return }
                            toast(l("举报已提交，拉黑未完成","Report submitted. Blocking didn’t complete."))
                            return
                        }
                    }
                    if reportId == id, utility == "report" { closeReport() }
                    if block { await refreshServerFeed() }
                    toast(block ? l("已举报并拉黑","Reported and blocked") : l("举报已提交","Report submitted"))
                } catch {
                    guard serverViewer == viewer else { return }
                    toast(l("举报未能确认，请稍后重试","Couldn’t confirm the report. Try again later."))
                }
            }
            return
        }
        recordReport(raw,details:details)
        if block, let author = reportAuthorID {
            recordBlock(NativeBlockedRecord(id:author,nickname:details.targetNickname,blockedAt:Date(),server:false))
        }
        closeReport()
        if block {
            rebuildVisibleStories()
            if let reply = selectedReply { selectedReply = discussionStory?.answers.first { $0.id == reply.id } }
        }
        persistLocal()
        toast(block ? l("举报已保存在本机，已拉黑","Report saved on this device and user blocked")
                    : l("举报已保存在本机","Report saved on this device"))
    }

    func updatePage(width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        VStack(alignment:.leading,spacing:0){
            HStack(spacing:10){
                Button {writingFocused=false;openUtility("more")} label:{Text("‹").font(.system(size:32,weight:.light)).foregroundColor(Color(hex:0x75666d)).frame(width:44,height:44)}.accessibilityLabel(l("返回","Back"))
                Text(l("补充进展","Add an update")).font(.system(size:19,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                Spacer()
            }.padding(.horizontal,16).padding(.top,top+12).padding(.bottom,14)
            ScrollView {
                VStack(spacing:12) {
                    GrowField(text:$updateText,height:.constant(150),focused:$writingFocused,maxHeight:150,
                              label:l("进展正文","Update text"),prompt:l("后来怎么样了？","What happened next?"))
                        .frame(height:150).background(Color(hex:0xf7f1ee),in:RoundedRectangle(cornerRadius:17))
                        .overlay(RoundedRectangle(cornerRadius:17).stroke(Color(hex:0xf0e7e2),lineWidth:1))
                    Button {saveUpdate()} label:{
                        Text(l("保存进展","Save update")).font(.system(size:15,weight:.bold)).foregroundColor(.white)
                            .frame(maxWidth:.infinity,minHeight:46).background(Color(hex:0xc8786d),in:RoundedRectangle(cornerRadius:14))
                    }
                }.padding(.horizontal,20).padding(.bottom,keyboardHeight > 0 ? 12 : bottom+16)
            }
        }.frame(width:width,height:max(1,height-keyboardHeight),alignment:.top)
            .frame(width:width,height:height,alignment:.top).background(Color(hex:0xfffbf9))
    }

    func saveUpdate(){
        let text=updateText.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, let story = model.current, story.id.hasPrefix("local-"),
              story.created/1000+86400 > Date().timeIntervalSince1970, requireLogin("update") else { return }
        rememberExpiry(of: story)
        updates[story.id,default:[]].append(text)
        updateText="";writingFocused=false;persistLocal()
        withAnimation(transitionAnimation){utility=nil}
        toast(l("进展已保存","Update saved"))
    }
    func appendReply(_ answer:NativeAnswer){
        guard let text = musicPayload(replyText,draft:replyMusic), requireLogin("reply") else { return }
        guard let story = discussionStory, story.created/1000+86400 > Date().timeIntervalSince1970,
              story.answers.contains(where: { $0.id == answer.id }) else { return }
        if usesLiveFeed && model.sourceStories.contains(where: { $0.id == story.id && $0.answers.contains { $0.id == answer.id } }) {
            let draft = replyText, attachment = replyMusic
            writeToServer("replies",fields:["answerId":answer.id,"text":text]) { _ in
                if discussionID == story.id, selectedReply?.id == answer.id, replyText == draft, replyMusic?.id == attachment?.id {
                    replyText = ""; replyMusic = nil; replyFocused = false
                }
                toast(l("回复已发布","Reply posted"))
            }
            return
        }
        let id = UUID().uuidString
        localState.replies[answer.id,default:[]].append(NativeReply(id:id,author:myName,text:text))
        localState.replyOwnership = (localState.replyOwnership ?? []).union([id])
        var parents = localState.replyStory ?? [:]
        parents[answer.id] = story.id
        localState.replyStory = parents
        rememberExpiry(of: story)
        replyText = ""; replyMusic = nil; replyFocused = false
        rebuildVisibleStories()
        selectedReply = discussionStory?.answers.first { $0.id == answer.id }
        persistLocal()
    }
    func detailPage(_ story:NativeStory,width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        ZStack(alignment:.top){
            H5Design.card
                .background(Color(hex:0xfffbf8))
                .allowsHitTesting(false)
            VStack(spacing:0){
                HStack{
                    Button {withAnimation(transitionAnimation){detailStory=nil}} label:{Text("‹").font(.system(size:32,weight:.light)).foregroundColor(Color(hex:0x6a5457)).frame(width:44,height:44)}.accessibilityLabel(l("返回","Back"))
                    Spacer()
                }.padding(.horizontal,10).padding(.top,top+6).modifier(DetailAddition())
                ScrollView {
                    VStack(alignment:.leading,spacing:0){
                        Text(l("一则匿名心事","AN ANONYMOUS THOUGHT")).font(.system(size:10,weight:.semibold)).kerning(1.2).foregroundColor(Color(hex:0x8f7274)).padding(.top,10).modifier(DetailAddition())
                        storyTitle(story,width:width)
                            .frame(width:max(1,width-104))
                            .frame(maxWidth:.infinity)
                            .modifier(StoryTitlePosition(id:story.id,namespace:storyTitleMotion,destination:true,expanded:true,enabled:!detailFromLibrary))
                            .padding(.top,16)
                        if let detail = story.detail, !detail.isEmpty {
                            Text(detail).font(.system(size:16)).lineSpacing(6)
                                .foregroundColor(Color(hex:0x433539))
                                .fixedSize(horizontal:false,vertical:true).padding(.top,18).modifier(DetailAddition())
                        }
                        Text("✦").font(.system(size:15)).foregroundColor(Color(hex:0xc49a8f)).frame(maxWidth:.infinity).padding(.top,26).modifier(DetailAddition())
                        ForEach(updates[story.id] ?? [],id:\.self){u in
                            Text(l("后续进展","Update")+" · "+u).font(.system(size:12)).foregroundColor(Color(hex:0x816e75)).padding(.top,10).modifier(DetailAddition())
                        }
                        Text("◷ \(story.hoursRemaining()) \(l("小时后消失","hours left"))  ·  \(story.answers.count) \(l("条建议","responses"))").font(.system(size:12)).foregroundColor(Color(hex:0x9a8888)).padding(.top,18).modifier(DetailAddition())
                    }.padding(.horizontal,26).padding(.bottom,40)
                }
                Text(l("点一下小伙伴，看看两边的想法","Tap a companion to see each side")).font(.system(size:11)).foregroundColor(Color(hex:0x8b7678)).padding(.bottom,bottom+22).modifier(DetailAddition())
            }
            .frame(width:width,height:height)
        }.frame(width:width,height:height)
    }
    func storyContentTransition(_ story: NativeStory,width: CGFloat,height: CGFloat) -> AnyTransition {
        if detailFromLibrary { return .move(edge:.trailing) }
        let area = max(1,height-265)
        let cardHeight = H5Design.cardHeight(story.text,width:width,available:area)
        let card = CGRect(x:26,y:100+(area-cardHeight)/2,width:max(1,width-52),height:cardHeight)
        return fullCardReveal(from:card,width:width,height:height,radius:30)
    }

    func snapshotPage(_ story:NativeStory,width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        VStack(alignment:.leading,spacing:0){
            HStack(spacing:10){
                Button {withAnimation(transitionAnimation){snapshotStory=nil}} label:{Text("‹").font(.system(size:32,weight:.light)).foregroundColor(Color(hex:0x75666d)).frame(width:44,height:44)}.accessibilityLabel(l("返回","Back"))
                VStack(alignment:.leading,spacing:2){
                    Text(l("大家的建议","The conversation")).font(.system(size:19,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                    Text(l("私密快照 · 只读","Private snapshot · read only")).font(.system(size:11)).foregroundColor(Color(hex:0x988b88))
                }
                Spacer()
            }.padding(.horizontal,16).padding(.top,top+12).padding(.bottom,113)
            ScrollView {
                VStack(alignment:.leading,spacing:10){
                    Text(l("这是你保存的私密快照，原始烦恼到期后会一起删除。","A private copy; it is deleted when the original story expires.")).font(.system(size:11)).foregroundColor(Color(hex:0x9b8f8b)).padding(.bottom,2)
                    Text(story.text).font(.system(size:16,weight:.semibold)).foregroundColor(Color(hex:0x433539)).fixedSize(horizontal:false,vertical:true)
                    if let detail=story.detail,!detail.isEmpty { Text(detail).font(.system(size:14)).foregroundColor(Color(hex:0x6d5f66)).fixedSize(horizontal:false,vertical:true) }
                    ForEach(updates[story.id] ?? [],id:\.self){u in Text(l("后续进展","Update")+" · "+u).font(.system(size:12)).foregroundColor(Color(hex:0x816e75)) }
                    Divider().padding(.vertical,4)
                    ForEach(story.answers){a in
                        VStack(alignment:.leading,spacing:6){
                            Text((a.side=="angel" ? l("天使","Angel"):l("恶魔","Devil")) + " · " + a.author).font(.system(size:11,weight:.bold)).foregroundColor(a.side=="angel" ? Color(hex:0x628fa9):Color(hex:0xc6786d))
                            Text(a.text).font(.system(size:14)).foregroundColor(Color(hex:0x59484b)).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                            ForEach(Array(a.replies.enumerated()),id:\.offset){ _,r in
                                Text("✦ "+r.text).font(.system(size:12)).foregroundColor(Color(hex:0x817276)).padding(.leading,8).fixedSize(horizontal:false,vertical:true)
                            }
                        }.padding(15).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).stroke(Color(hex:0xf0e9e7),lineWidth:1))
                    }
                }.padding(.horizontal,20).padding(.bottom,bottom+20)
            }
        }.frame(width:width,height:height,alignment:.top).background(Color(hex:0xeef8ff))
    }

    // MARK: - Profile
    func profilePage(width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        let owned = ownedAnswerIDs
        let answers = model.stories.reduce(0) { $0 + $1.answers.filter { owned.contains($0.id) }.count }
        let columns = [GridItem(.flexible(),spacing:10),GridItem(.flexible(),spacing:10)]
        return VStack(spacing:0){
            HStack{
                Text(l("我的","Me")).font(.system(size:19,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                Spacer()
            }.frame(height:44).padding(.horizontal,16).padding(.top,top+8)
            ScrollView {
                VStack(alignment:.leading,spacing:0){
                    if model.preview || auth.accountAccessEnabled { accountSection.padding(.top,8) }
                    LazyVGrid(columns:columns,spacing:10){
                        Button {openUtility("profile-stories")} label:{profileTile("✎",iconBG:0xfae7e2,iconColor:0xbe7770,label:l("我的烦恼","My stories"),count:model.stories.filter{$0.id.hasPrefix("local-") || $0.mine == true}.count)}
                        Button {openUtility("profile-answers")} label:{profileTile("✧",iconBG:0xe7f1f6,iconColor:0x789fb2,label:l("我的建议","My responses"),count:answers,unread:unreadReplyCount)}
                        Button {openUtility("saved")} label:{profileTile("♡",iconBG:0xfaeee6,iconColor:0xc58c78,label:l("收藏","Saved"),count:snapshots.count)}
                        Button {openUtility("activity")} label:{profileTile("◌",iconBG:0xefecf3,iconColor:0xa096b0,label:l("举报记录","Report history"),count:reports.isEmpty ? nil:reports.count)}
                        Button {openUtility("blocked")} label: {
                            profileTile("⊘",iconBG:0xf1ebe9,iconColor:0x89716f,label:l("黑名单","Blocked users"),count:nil)
                        }
                    }.padding(.top,12)
                    Button { openUtility("help-privacy") } label: {
                        HStack(spacing:6) {
                            Text(l("帮助与隐私","Help & privacy"))
                            Image(systemName:"chevron.right").font(.system(size:9,weight:.semibold))
                        }.font(.system(size:12,weight:.medium)).foregroundColor(Color(hex:0x8a666d))
                            .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(PressScale()).padding(.top,12)
                }.padding(.horizontal,18).padding(.bottom,bottom+H5Design.navigationHeight+12)
            }
        }.frame(width:width,height:height).background(Color(hex:0xfffbf9))
            .animation(transitionAnimation,value:auth.userId)
            .alert(isPresented:$confirmDeleteAccount){
                Alert(
                    title:Text(l("删除账号？","Delete account?")),
                    message:Text(l("下一步需要输入 iPhone 锁屏密码。此操作会请求删除账号及其在线数据，并使该账号的登录失效。备份或已交给第三方处理的副本不一定同步删除。","Next, enter your iPhone passcode. This requests deletion of your account and its online data and invalidates its sessions. Backup copies or copies already shared for third-party processing may not be deleted at the same time.")),
                    primaryButton:.destructive(Text(l("删除","Delete"))){deleteAccountAndData()},
                    secondaryButton:.cancel(Text(l("取消","Cancel")))
                )
            }
    }
    var accountSection: some View {
        Group {
            if let account=auth.account {
                let nickname = account.nickname.flatMap { $0.isEmpty ? nil : $0 }
                VStack(alignment:.leading,spacing:0){
                    HStack(alignment:.top,spacing:10){
                        VStack(alignment:.leading,spacing:5){
                            Text(nickname ?? l("未设置昵称","No nickname yet")).font(.system(size:20,weight:.bold)).foregroundColor(Color(hex:0xffeed1))
                            HStack(spacing:5){
                                Text("ID").font(.system(size:9,weight:.bold)).foregroundColor(Color(hex:0xf0cb85)).padding(.horizontal,5).padding(.vertical,2).background(Color(hex:0x4c3e2a),in:Capsule())
                                Text(account.public_id ?? "—").font(.system(size:12,weight:.medium,design:.monospaced)).foregroundColor(Color(hex:0xd7ba8c))
                            }
                        }
                        Spacer(minLength:0)
                        Button { openNicknameEditor() } label: {
                            Label(l("修改昵称","Edit nickname"),systemImage:"pencil")
                                .font(.system(size:12)).foregroundColor(Color(hex:0xe9dfd1))
                                .padding(.horizontal,10).frame(minHeight:44)
                        }.buttonStyle(PressScale()).disabled(auth.busy)
                    }
                    HStack(spacing:9){
                        Button {
                            Task {
                                guard await auth.signOut() else { return }
                                toast(l("已退出登录","Signed out"))
                            }
                        } label:{
                            Text(l("退出登录","Sign out")).font(.system(size:12)).foregroundColor(Color(hex:0xe9dfd1)).padding(.horizontal,13).frame(height:36).background(Color(hex:0x363230),in:Capsule())
                        }.buttonStyle(PressScale())
                        Button {confirmDeleteAccount=true} label:{
                            Text(l("删除账号","Delete account")).font(.system(size:12)).foregroundColor(Color(hex:0xf3b1a7)).padding(.horizontal,13).frame(height:36).background(Color(hex:0x4a302e),in:Capsule())
                        }.buttonStyle(PressScale())
                        Spacer(minLength:0)
                    }.padding(.top,12)
                    if let error=auth.errorText { Text(error).font(.system(size:11)).foregroundColor(Color(hex:0xf3b1a7)).padding(.top,8) }
                }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                    .background {
                        let shape = RoundedRectangle(cornerRadius:20)
                        shape.fill(LinearGradient(colors:[Color(hex:0x35312d),Color(hex:0x151417)],
                                                  startPoint:.topLeading,endPoint:.bottomTrailing))
                            .overlay {
                                Canvas { context, size in
                                    var lines = Path()
                                    for x in stride(from:-size.height,through:size.width,by:9.0) {
                                        lines.move(to:CGPoint(x:x,y:size.height))
                                        lines.addLine(to:CGPoint(x:x+size.height,y:0))
                                    }
                                    context.stroke(lines,with:.color(Color(hex:0xd5ae70).opacity(0.13)),lineWidth:0.5)
                                }.clipShape(shape).allowsHitTesting(false)
                            }
                    }
                    .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Color(hex:0xb2905d).opacity(0.75),lineWidth:1))
                    .shadow(color:.black.opacity(0.20),radius:10,y:4)
                    .transition(.opacity)
            } else {
                VStack(alignment:.leading,spacing:0){
                    Text(l("你正在以游客身份浏览","You’re browsing as a guest")).font(.system(size:18,weight:.bold)).foregroundColor(Color(hex:0x3a3038))
                    Text(l("登录后可以发布、回复、点赞和收藏。","Sign in to share, respond, like and save.")).font(.system(size:12)).foregroundColor(Color(hex:0x8d7c7d)).lineSpacing(4).fixedSize(horizontal:false,vertical:true).padding(.top,8)
                    AppleSignInControl(auth:auth).padding(.top,15)
                    if let error=auth.errorText { Text(error).font(.system(size:11)).foregroundColor(Color(hex:0xb85657)).padding(.top,9) }
                }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                    .background(.white,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(Color(hex:0xf1e7e2),lineWidth:1))
                    .transition(.opacity)
            }
        }.animation(transitionAnimation,value:auth.userId)
    }
    func openNicknameEditor(){
        nicknameDraft=auth.account?.nickname ?? ""
        nicknameError=nil
        withAnimation(transitionAnimation){nicknameMode=true}
        DispatchQueue.main.asyncAfter(deadline:.now()+0.32){if nicknameMode { nicknameFocused=true }}
    }
    private func supportAddress(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey:key) as? String else { return nil }
        let address = value.trimmingCharacters(in:.whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    private func supportPageURL(_ key: String) -> URL? {
        guard let address = supportAddress(key), let url = URL(string:address),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    private var supportEmailURL: URL? {
        let address = supportAddress("BetweenSupportEmail") ?? "zzrzzr0815@gmail.com"
        guard address.range(of:"^[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$",options:.regularExpression) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        return components.url
    }

    private var moderationPrivacyAction: some View {
        VStack(alignment:.leading,spacing:8) {
        if !model.preview && moderationConsent {
            moreRow(l("撤回审核授权","Withdraw moderation consent")) {
                moderationConsent = false
                let viewer = serverViewer
                Task {
                    do {
                        _ = try await model.mutate("ai-consent/withdraw",fields:[:],viewer:viewer)
                        toast(l("已撤回并取消待处理任务；已发送的请求无法收回","Consent withdrawn and pending jobs cancelled. Requests already sent cannot be recalled."))
                    } catch {
                        toast(l("本机已撤回；服务器任务未确认取消","Withdrawn on this device. Server cancellation was not confirmed."))
                    }
                }
            }
        }
        }
    }

    private func helpPrivacyPage(width:CGFloat,height:CGFloat,bottom:CGFloat)->some View {
        let privacy = supportPageURL("BetweenPrivacyPolicyURL") ?? URL(string:"https://minglimaster.com/between/privacy.html")
        let email = supportEmailURL
        return VStack(alignment:.leading,spacing:4) {
            sheetHead(l("帮助与隐私","Help & privacy"),top:0)
            VStack(spacing:8) {
                if let privacy {
                    moreRow(l("隐私政策","Privacy policy")) { UIApplication.shared.open(privacy) }
                }
                if let email {
                    moreRow(l("邮件客服","Email support")) { UIApplication.shared.open(email) }
                }
                moderationPrivacyAction
            }.padding(.horizontal,20).padding(.vertical,4)
        }.padding(.bottom,bottom+12).frame(width:width).background(Color(hex:0xfffbf9))
            .clipShape(TopRoundedShape(radius:26))
            .frame(width:width,height:height,alignment:.bottom)
    }

    func deleteAccountAndData(){
        let key = localKey
        Task {
            if await auth.deleteAccount() {
                NativeLocalStorage.remove(from:.standard,key:key)
                reloadLocalForAccount()
                withAnimation(transitionAnimation){utility=nil;nicknameMode=false;loginPrompt="register"}
                toast(l("账号已删除","Account deleted"))
            }
        }
    }
    func saveNickname(){
        let oldName=auth.account?.nickname
        Task {
            if let message=await auth.submitNickname(nicknameDraft) {
                nicknameError=message
            } else {
                nicknameError=nil;nicknameFocused=false
                if let oldName, let newName=auth.account?.nickname, oldName != newName {
                    renameLocalAuthor(to:newName)
                }
                withAnimation(transitionAnimation){nicknameMode=false}
            }
        }
    }
    func loginPromptCard(_ reason:String,width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        let title:String
        switch reason {
        case "register": title=l("注册新账号","Create a new account")
        case "publish": title=l("登录后就能发布烦恼","Sign in to share a story")
        case "respond", "reply": title=l("登录后就能加入讨论","Sign in to join the conversation")
        case "like": title=l("登录后就能点赞","Sign in to like")
        case "save": title=l("登录后就能收藏","Sign in to save")
        case "update": title=l("登录后就能补充进展","Sign in to add an update")
        case "best": title=l("登录后就能选出最佳建议","Sign in to choose a best response")
        case "report": title=l("登录后就能举报","Sign in to report")
        default: title=l("登录后继续","Sign in to continue")
        }
        return ZStack(alignment:.bottom){
            Color(hex:0x302532).opacity(0.34).contentShape(Rectangle()).onTapGesture{withAnimation(transitionAnimation){loginPrompt=nil}}.transition(.opacity)
            VStack(alignment:.leading,spacing:0){
                HStack{
                    Text(title).font(.system(size:18,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                    Spacer(minLength:0)
                    Button {withAnimation(transitionAnimation){loginPrompt=nil}} label:{Text("×").font(.system(size:24,weight:.light)).foregroundColor(Color(hex:0x8d7c7d)).frame(width:34,height:34)}.accessibilityLabel(l("关闭","Close"))
                }
                AppleSignInControl(auth:auth).padding(.top,14)
                if let error=auth.errorText { Text(error).font(.system(size:11)).foregroundColor(Color(hex:0xb85657)).padding(.top,9) }
                Button {withAnimation(transitionAnimation){loginPrompt=nil}} label:{
                    Text(l("稍后再说","Not now")).font(.system(size:12)).foregroundColor(Color(hex:0xa29490)).frame(maxWidth:.infinity,minHeight:40)
                }.buttonStyle(PressScale()).padding(.top,6)
            }.padding(20).frame(width:width-36)
                .background(Color(hex:0xfffbf9),in:RoundedRectangle(cornerRadius:22))
                .shadow(color:Color(hex:0x45313a).opacity(0.18),radius:24,y:14)
                .padding(.bottom,max(bottom+22,keyboardHeight+22))
        }.frame(width:width,height:height).transition(.opacity)
    }
    func nicknameSheet(width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        ZStack(alignment:.bottom){
            Color(hex:0x302532).opacity(0.34).contentShape(Rectangle()).onTapGesture{closeNicknameSheet()}.transition(.opacity)
            VStack(alignment:.leading,spacing:0){
                HStack{
                    Text(auth.displayName.isEmpty ? l("设置昵称","Set nickname") : l("修改昵称","Edit nickname")).font(.system(size:18,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                    Spacer(minLength:0)
                    Button {closeNicknameSheet()} label:{Text("×").font(.system(size:24,weight:.light)).foregroundColor(Color(hex:0x8d7c7d)).frame(width:34,height:34)}.accessibilityLabel(l("关闭","Close"))
                }
                ZStack(alignment:.leading){
                    if nicknameDraft.isEmpty { Text(l("例如：晚风","e.g. Nightfall")).font(.system(size:16)).foregroundColor(Color(hex:0xb3a5a0)).padding(.leading,14).allowsHitTesting(false) }
                    TextField("",text:$nicknameDraft).font(.system(size:16)).foregroundColor(Color(hex:0x3a3038)).padding(.horizontal,14).frame(height:50)
                        .disableAutocorrection(true)
                        .focused($nicknameFocused)
                        .onChange(of:nicknameDraft){ value in if value.count>16 {nicknameDraft=String(value.prefix(16))} }
                }.background(Color(hex:0xf7f1ee),in:RoundedRectangle(cornerRadius:15)).overlay(RoundedRectangle(cornerRadius:15).stroke(Color(hex:0xeee4df),lineWidth:1)).padding(.top,16)
                HStack{
                    Text(nicknameError ?? l("2–16 个汉字或英文字母，不可填写联系方式","2–16 Chinese or English letters. No contact details.")).font(.system(size:11)).foregroundColor(nicknameError==nil ? Color(hex:0xa29490):Color(hex:0xb85657)).lineSpacing(3)
                    Spacer(minLength:0)
                    Text("\(nicknameDraft.count)/16").font(.system(size:10)).foregroundColor(Color(hex:0xb0a29d))
                }.padding(.top,9)
                Button {saveNickname()} label:{
                    HStack(spacing:6){Text(l("保存昵称","Save nickname"));Text("↗")}.font(.system(size:15,weight:.bold)).foregroundColor(.white).frame(maxWidth:.infinity,minHeight:48).background(Color(hex:0xc8786d),in:RoundedRectangle(cornerRadius:15)).opacity(auth.busy ? 0.6:1)
                }.buttonStyle(PressScale()).disabled(auth.busy).padding(.top,16)
            }.padding(20).frame(width:width-36)
                .background(Color(hex:0xfffbf9),in:RoundedRectangle(cornerRadius:22))
                .shadow(color:Color(hex:0x45313a).opacity(0.18),radius:24,y:14)
                .padding(.bottom,max(bottom+22,keyboardHeight+22))
        }.frame(width:width,height:height).transition(.opacity)
    }
    func closeNicknameSheet(){
        nicknameFocused=false
        nicknameError=nil
        withAnimation(transitionAnimation){nicknameMode=false}
    }
    func openUtility(_ page:String){withAnimation(transitionAnimation){utility=page}}
    func profileTile(_ icon:String,iconBG:UInt32,iconColor:UInt32,label:String,count:Int?,unread:Int = 0)->some View {
        VStack(alignment:.leading,spacing:0){
            Text(icon).font(.system(size:20)).foregroundColor(Color(hex:iconColor)).frame(width:34,height:34).background(Color(hex:iconBG),in:RoundedRectangle(cornerRadius:12))
            Spacer(minLength:12)
            HStack(alignment:.firstTextBaseline,spacing:7){
                Text(label).font(.system(size:13,weight:.bold)).foregroundColor(Color(hex:0x59484b))
                if let count { Text("\(count)").font(.system(size:11,weight:.medium)).foregroundColor(Color(hex:0xb5a39e)) }
            }
        }.padding(13).frame(maxWidth:.infinity,minHeight:114,alignment:.leading)
            .background(.white,in:RoundedRectangle(cornerRadius:19)).overlay(RoundedRectangle(cornerRadius:19).stroke(Color(hex:0xf2e8e3),lineWidth:1))
            .overlay(alignment:.topTrailing) {
                Group {
                    if unread > 0 { replyBadge(unread) }
                    else { Text("↗").font(.system(size:15)).foregroundColor(Color(hex:0xc5b5af)) }
                }.padding(15)
            }
    }
    private func blockedPage(width: CGFloat,height: CGFloat,top: CGFloat,bottom: CGFloat) -> some View {
        let local = localState.blockedRecords ?? []
        let legacy = (localState.blockedAuthorIDs ?? []).subtracting(local.filter { !$0.server }.map(\.id))
        let remote = (onlineBlockedUsers ?? []).map { entry in
            NativeBlockedRecord(id:entry.id,nickname:local.first { $0.server && $0.id == entry.id }?.nickname,
                                blockedAt:Date(timeIntervalSince1970:entry.blockedAt),server:true)
        }
        let records = (remote + local.filter { !$0.server }).sorted { $0.blockedAt > $1.blockedAt }
        return VStack(alignment:.leading,spacing:12) {
            HStack(spacing:10) {
                Button { openUtility("profile") } label: {
                    Image(systemName:"chevron.left").frame(width:44,height:44)
                }.accessibilityLabel(l("返回","Back"))
                Text(l("黑名单","Blocked users")).font(.system(size:19,weight:.bold))
                Spacer()
            }
            ScrollView {
                LazyVStack(alignment:.leading,spacing:10) {
                    if blockedListError {
                        Button(l("加载失败，重试","Couldn’t load. Retry")) { Task { await loadBlockedUsers() } }
                            .font(.system(size:14)).foregroundColor(H5Design.muted)
                            .frame(maxWidth:.infinity,minHeight:44)
                    } else if usesLiveFeed && onlineBlockedUsers == nil {
                        ProgressView().frame(maxWidth:.infinity,minHeight:44)
                    } else if records.isEmpty && legacy.isEmpty {
                        Text(l("黑名单为空","No blocked users"))
                            .font(.system(size:14)).foregroundColor(H5Design.muted)
                            .frame(maxWidth:.infinity).padding(.vertical,24)
                    }
                    ForEach(records) { record in
                        blockedRow(record, subtitle:record.blockedAt.formatted(date:.abbreviated,time:.shortened))
                    }
                    ForEach(legacy.sorted(),id:\.self) { id in
                        blockedRow(NativeBlockedRecord(id:id,nickname:nil,blockedAt:.distantPast,server:false),
                                   subtitle:l("本机拉黑","Blocked on this device"))
                    }
                }.padding(.bottom,12)
            }
        }.padding(.horizontal,20).padding(.top,top+8).padding(.bottom,bottom+H5Design.navigationHeight+12)
            .frame(width:width,height:height,alignment:.top)
            .background(Color(hex:0xfffaf8))
            .task(id:serverViewer) { await loadBlockedUsers() }
            .confirmationDialog(l("解除拉黑？","Unblock this user?"),isPresented:Binding(
                get:{ unblockTarget != nil },set:{ if !$0 { unblockTarget = nil } }),
                                titleVisibility:.visible,presenting:unblockTarget) { record in
                Button(l("解除拉黑","Unblock"),role:.destructive) { unblock(record) }
                Button(l("取消","Cancel"),role:.cancel) {}
            } message: { record in
                Text(record.nickname ?? l("匿名用户","Anonymous user"))
            }
    }

    private func loadBlockedUsers() async {
        blockedListError = false
        guard usesLiveFeed else { return }
        let viewer = serverViewer
        do {
            let records = try await model.fetchBlockedUsers(viewer:viewer)
            if serverViewer == viewer && !Task.isCancelled { onlineBlockedUsers = records }
        } catch {
            if serverViewer == viewer && !Task.isCancelled { blockedListError = true }
        }
    }

    private func blockedRow(_ record: NativeBlockedRecord,subtitle: String) -> some View {
        HStack(spacing:12) {
            VStack(alignment:.leading,spacing:5) {
                Text(record.nickname ?? l("匿名用户","Anonymous user")).font(.system(size:14,weight:.semibold))
                Text(subtitle).font(.system(size:12)).foregroundColor(H5Design.muted)
            }
            Spacer(minLength:4)
            Button(l("解除","Unblock")) { unblockTarget = record }
                .font(.system(size:13,weight:.semibold)).foregroundColor(Color(hex:0xb05e61))
                .frame(minHeight:44).disabled(serverWriteInFlight)
        }.padding(.horizontal,14).padding(.vertical,6)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(.white,in:RoundedRectangle(cornerRadius:15))
    }

    private func unblock(_ record: NativeBlockedRecord) {
        func clear() {
            localState.blockedRecords?.removeAll { $0.id == record.id && $0.server == record.server }
            if record.server { onlineBlockedUsers?.removeAll { $0.id == record.id } }
            else {
                localState.blockedAuthorIDs?.remove(record.id)
                rebuildVisibleStories()
            }
            persistLocal()
            toast(l("已解除拉黑","User unblocked"))
        }
        if record.server {
            writeToServer("unblock-user",fields:["id":record.id]) { _ in clear() }
        } else {
            clear()
        }
    }

    func libraryPage(_ page:String,width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        let owned = ownedAnswerIDs
        let title:String, intro:String, empty:String
        switch page {
        case "profile-stories": title=l("我的烦恼","My stories");intro=l("写下的心事，会在这里停留 24 小时。","Your stories stay here for 24 hours.");empty=l("还没有发布过烦恼。","You haven’t shared a story yet.")
        case "profile-answers": title=l("我的建议","My responses");intro=l("你留下的建议，都在这里。","The conversations you have joined.");empty=l("还没有发表过建议。","You haven’t shared a response yet.")
        case "saved": title=l("我的私密快照","Your private snapshots");intro=l("应用内的只读讨论副本，烦恼到期或被移除时一同删除。","Read-only copies in the app. They are deleted when the original story expires or is removed.");empty=l("还没有收藏过讨论。","No saved discussions yet.")
        default: title=l("举报记录","Report history");intro=l("这里会显示保存在本机的举报。","Reports saved on this device appear here.");empty=l("暂时没有新动态","Nothing new here yet")
        }
        var items:[(String,String,NativeStory?,String?)] = []
        if page=="profile-answers" { for story in model.stories { for answer in story.answers where owned.contains(answer.id) { items.append((answer.text,story.text,story,answer.id)) } } }
        if page=="profile-stories" { for story in model.stories where story.id.hasPrefix("local-") || story.mine == true { items.append((story.text,l("24 小时后消失","Expires in 24 hours"),story,nil)) } }
        if page=="saved" { for story in snapshots.compactMap({ localState.filteringBlockedAuthors(in:$0) }) { items.append((story.text,l("快照 · 只读","Snapshot · read only"),story,nil)) } }
        if page=="activity" {
            for raw in reports.reversed() {
                let details = reportDetails(raw)
                items.append((details.content ?? l("内容已不可用","Content unavailable"),
                              reportStatus(details) + " · " + reportTypeLabel(raw),nil,raw))
            }
        }
        return VStack(alignment:.leading,spacing:0){
            HStack(spacing:10){
                Button {openUtility("profile")} label:{Text("‹").font(.system(size:32,weight:.light)).foregroundColor(Color(hex:0x75666d)).frame(width:44,height:44)}.accessibilityLabel(l("返回","Back"))
                Text(title).font(.system(size:19,weight:.bold)).foregroundColor(Color(hex:0x302b32))
                Spacer()
            }.frame(height:44).padding(.horizontal,16).padding(.top,top+8)
            ScrollView {
                VStack(alignment:.leading,spacing:12){
                    Text(intro).font(.system(size:12)).foregroundColor(Color(hex:0xa29894)).lineSpacing(4).padding(.top,4)
                    if page == "activity" && usesLiveFeed {
                        ReportFeedbackSection(model:model,viewer:serverViewer,chinese:zh).id(serverViewer)
                    }
                    if items.isEmpty {
                        Text(empty).font(.system(size:14)).foregroundColor(Color(hex:0xa09494)).frame(maxWidth:.infinity).padding(.vertical,35)
                    }
                    ForEach(Array(items.enumerated()),id:\.offset){ index,item in
                        let frameKey = "library-\(page)-\(index)"
                        VStack(alignment:.leading,spacing:5) {
                            VStack(alignment:.leading,spacing:8) {
                                HStack {
                                    Text(title).font(.system(size:11)).foregroundColor(Color(hex:0xb0a29d))
                                    Spacer()
                                    if page == "profile-answers", let answer = item.2?.answers.first(where: { $0.id == item.3 }) {
                                        let unread = unreadReplyIDs(in:answer).count
                                        if unread > 0 { replyBadge(unread) }
                                    }
                                }
                                Text(item.0).font(.system(size:14)).foregroundColor(Color(hex:0x59484b)).fixedSize(horizontal:false,vertical:true)
                                Text(item.1).font(.system(size:12)).foregroundColor(Color(hex:0x9b8d8b)).lineLimit(2)
                            }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                                .onTapGesture {
                                    switch page {
                                    case "saved":
                                        if let story = item.2 {
                                            snapshotOrigin = cardFrames[frameKey]
                                            withAnimation(transitionAnimation){snapshotStory=story}
                                        }
                                    case "profile-answers":
                                        guard let story = item.2, let answer = story.answers.first(where: { $0.id == item.3 }) else { return }
                                        discussionID = story.id
                                        openReply(answer)
                                    case "activity":
                                        if let key = item.3 {
                                            reportOrigin = cardFrames[frameKey]
                                            withAnimation(transitionAnimation) { selectedReport = key }
                                        }
                                    default: if let story=item.2 {openDetail(story)}
                                    }
                                }
                            if page == "profile-answers", let story = item.2 {
                                Button { openDetail(story) } label: {
                                    Label(l("查看原帖","View original"),systemImage:"arrow.up.right")
                                        .font(.system(size:12,weight:.semibold))
                                        .foregroundColor(Color(hex:0x4d7188))
                                        .padding(.horizontal,10).frame(minHeight:44)
                                        .contentShape(Rectangle())
                                }.buttonStyle(PressScale())
                            }
                        }.padding(15).frame(maxWidth:.infinity,alignment:.leading)
                            .background(.white,in:RoundedRectangle(cornerRadius:16))
                            .overlay(RoundedRectangle(cornerRadius:16).stroke(Color(hex:0xf0e9e7),lineWidth:1).allowsHitTesting(false))
                            .background {
                                if (page == "saved" && item.2 != nil) || page == "activity" {
                                    GeometryReader { proxy in
                                        Color.clear.preference(key:CardFrames.self,
                                                               value:[frameKey:proxy.frame(in:.named("card-stage"))])
                                    }
                                }
                            }
                    }
                }.padding(.horizontal,20).padding(.bottom,bottom+H5Design.navigationHeight+12)
            }
        }.frame(width:width,height:height).background(Color(hex:0xfffaf8))
    }

    private func reportParts(_ key: String) -> [String] {
        key.split(separator:"|",omittingEmptySubsequences:false).map(String.init)
    }
    private func reportTypeLabel(_ key: String) -> String {
        switch reportParts(key).dropFirst().first {
        case "answer": return l("建议","Response")
        case "reply": return l("回复","Reply")
        default: return l("烦恼","Story")
        }
    }
    private func reportDetails(_ key: String) -> NativeReportDetails {
        var record = localState.reportDetails?[key] ?? NativeReportDetails()
        if record.targetNickname != nil { return record }
        let parts = reportParts(key)
        guard parts.count >= 3, let story = model.stories.first(where: { $0.id == parts[0] })
                ?? model.sourceStories.first(where: { $0.id == parts[0] }) else { return record }
        switch parts[1] {
        case "answer":
            if let answer = story.answers.first(where: { $0.id == parts[2] }) {
                record.content = record.content ?? answer.text
                record.camp = record.camp ?? answer.side
                record.targetNickname = answer.author
                record.targetPublicID = answer.publicAuthorID
            }
        case "reply":
            for answer in story.answers {
                if let reply = answer.replies.first(where: { $0.id == parts[2] }) {
                    record.content = record.content ?? reply.text
                    record.camp = record.camp ?? answer.side
                    record.targetNickname = reply.author
                    record.targetPublicID = reply.publicAuthorID
                    break
                }
            }
        default:
            record.content = record.content ?? story.text
            record.targetNickname = story.author
            record.targetPublicID = story.publicAuthorID
        }
        return record
    }
    private func reportStatus(_ record: NativeReportDetails) -> String {
        record.acceptanceStatus ?? l("仅保存在本机，未送审","Saved on this device · not submitted")
    }
    func reportDetailCard(_ key: String,width: CGFloat,height: CGFloat,top: CGFloat,bottom: CGFloat) -> some View {
        let record = reportDetails(key)
        let reasonCode = reportParts(key).dropFirst(3).first
        let reason = reportReasons.first { $0.1 == reasonCode }?.0 ?? l("未记录","Not recorded")
        let direction: String? = record.camp == "angel" ? l("天使阵营","Angel")
            : record.camp == "devil" ? l("恶魔阵营","Devil") : nil
        let category = [reportTypeLabel(key),direction].compactMap { $0 }.joined(separator:" · ")
        let available = max(1,height-top-bottom-32)
        let cardHeight = min(360,available)
        let cardWidth = max(1,min(420,width-44))
        let target = CGRect(x:(width-cardWidth)/2,y:top+16+(available-cardHeight)/2,width:cardWidth,height:cardHeight)
        let ink = Color(hex:0x342a29)
        let muted = Color(hex:0x766561)
        let name = record.targetNickname ?? l("匿名用户","Anonymous user")
        let identity = record.targetPublicID.map { "\(name) · ID \($0)" } ?? name
        let shape = RoundedRectangle(cornerRadius:20)
        return ZStack(alignment:.topLeading) {
            VStack(alignment:.leading,spacing:0) {
                HStack {
                    Text(l("举报详情","Report details")).font(.system(size:20,weight:.semibold))
                    Spacer(minLength:8)
                    Button { withAnimation(transitionAnimation) { selectedReport = nil } } label: {
                        Image(systemName:"xmark").font(.system(size:13,weight:.semibold))
                            .foregroundColor(muted)
                            .frame(width:32,height:32).background(Color(hex:0xf1e9e3),in:Circle())
                            .frame(width:44,height:44).contentShape(Rectangle())
                    }.accessibilityLabel(l("关闭举报详情","Close report details"))
                }.padding(.leading,20).padding(.trailing,12).padding(.top,10)
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        HStack(alignment:.top,spacing:10) {
                            Circle().fill(record.result?.isEmpty == false ? Color(hex:0x52785c) : Color(hex:0x9e6b29))
                                .frame(width:7,height:7).padding(.top,5).accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:4) {
                                Text(reportStatus(record)).font(.system(size:14,weight:.semibold))
                                Text(record.result.flatMap { $0.isEmpty ? nil : $0 } ?? l("暂无处理结果","No outcome yet"))
                                    .font(.system(size:13)).foregroundColor(muted)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                        Divider().overlay(Color(hex:0xeee2d9))
                        VStack(spacing:7) {
                            reportMetadata(l("举报对象","Target"),identity,muted:muted)
                            reportMetadata(l("内容类型","Content type"),category,muted:muted)
                            reportMetadata(l("举报原因","Reason"),reason,muted:muted)
                            if let date = record.createdAt {
                                reportMetadata(l("记录时间","Recorded"),date.formatted(date:.abbreviated,time:.shortened),muted:muted)
                            }
                        }
                        VStack(alignment:.leading,spacing:6) {
                            Text(l("被举报内容","Reported content"))
                                .font(.system(size:12,weight:.semibold)).foregroundColor(muted)
                            Text(record.content ?? l("内容已不可用","Content unavailable"))
                                .font(.system(size:14)).lineSpacing(4)
                                .fixedSize(horizontal:false,vertical:true)
                                .frame(maxWidth:.infinity,alignment:.leading)
                                .padding(.leading,10)
                                .overlay(alignment:.leading) {
                                    Capsule().fill(Color(hex:0xc3a48d)).frame(width:2)
                                }
                        }
                    }.padding(.horizontal,20).padding(.top,8).padding(.bottom,20)
                }
            }.foregroundColor(ink)
                .frame(width:cardWidth,height:cardHeight)
                .background(Color(hex:0xfffbf7),in:shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color(hex:0xeee2d9),lineWidth:1))
                .position(x:target.midX,y:target.midY)
        }.frame(width:width,height:height)
            .transition(replyReveal(from:reportOrigin,to:target))
    }
    private func reportMetadata(_ label: String,_ value: String,muted: Color) -> some View {
        HStack(alignment:.firstTextBaseline,spacing:12) {
            Text(label).foregroundColor(muted)
            Spacer(minLength:4)
            Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)
        }.font(.system(size:13))
    }

    func openReply(_ answer: NativeAnswer) {
        composerFocused = false
        replyText = ""
        replyMusic = nil
        replyOrigin = cardFrames[answer.id]
        let unread = unreadReplyIDs(in:answer)
        if !unread.isEmpty {
            localState.seenIncomingReplies = (localState.seenIncomingReplies ?? []).union(unread)
            persistLocal()
        }
        withAnimation(transitionAnimation) { selectedReply = answer }
    }
    func closeReply() {
        replyFocused = false
        withAnimation(transitionAnimation) {
            selectedReply = nil
            if camp == nil { discussionID = nil }
        }
    }

    // MARK: - Reply layer
    func replyOverlay(_ answer:NativeAnswer,width:CGFloat,height:CGFloat,top:CGFloat,bottom:CGFloat)->some View {
        let lowerEdge = height - (keyboardHeight > 0 ? keyboardHeight+8 : bottom+18)
        let upperEdge = top+18
        let available = max(1,lowerEdge-upperEdge)
        let dialogH = min(available,height*0.74)
        let dialogCenter = upperEdge+available/2
        let dialogWidth = max(1,width-32)
        let side = NativeCamp(rawValue:answer.side)
        let accent = side?.accent ?? H5Design.muted
        let surface = side?.background ?? Color(hex:0xfffbf9)
        let fromLibrary = camp == nil
        return ZStack(alignment:.topLeading){
            (fromLibrary ? surface : Color.clear).contentShape(Rectangle()).onTapGesture{closeReply()}
            VStack(alignment:.leading,spacing:0){
                HStack(spacing:13){
                    Button {closeReply()} label:{Text("‹").font(.system(size:32,weight:.light)).foregroundColor(Color(hex:0x5d5055)).frame(width:42,height:42).background(Color(hex:0xf2eae6),in:Circle())}.accessibilityLabel(l("返回评论","Back to comments"))
                    Text(l("回复","Replies")).font(.system(size:18,weight:.bold)).foregroundColor(H5Design.ink)
                    Spacer(minLength:0)
                }.padding(.horizontal,20).padding(.top,16).padding(.bottom,14)
                ScrollView {
                    VStack(alignment:.leading,spacing:16){
                        VStack(alignment:.leading,spacing:8){
                            HStack{
                                Text(displayAuthor(answer)).font(.system(size:12,weight:.bold)).foregroundColor(Color(hex:0x9a8888))
                                if answer.author.contains("AI") { Text("AI").font(.system(size:9,weight:.bold)).foregroundColor(Color(hex:0xa87336)).padding(.horizontal,5).padding(.vertical,2).background(Color(hex:0xf7ead6),in:Capsule()) }
                                Spacer()
                                if !isOwnReportTarget("answer",answer.id,in:discussionStory) {
                                    Button {openReport("answer",answer.id)} label:{Text("⚑ "+l("举报","Report")).font(.system(size:11)).foregroundColor(Color(hex:0xb0a29d)).frame(height:26)}.buttonStyle(.plain)
                                }
                            }
                            answerText(answer.text,side:NativeCamp(rawValue:answer.side))
                                .frame(maxWidth:.infinity,alignment:.leading)
                            HStack(spacing:5){
                                Image(systemName:"heart").font(.system(size:14,weight:.light))
                                Text("\(answer.likes)").font(.system(size:12))
                            }.foregroundColor(Color(hex:0x897a7a)).padding(.horizontal,11).frame(height:36).background(Color(hex:0xf8f4f2),in:Capsule())
                        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(replyCardSurface,in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).strokeBorder(replyCardBorder,lineWidth:1))

                        if answer.replies.isEmpty {
                            Text(l("还没有回复，来接住这句话吧。","No replies yet. Be the first to respond.")).font(.system(size:14)).foregroundColor(Color(hex:0xa09494)).frame(maxWidth:.infinity).padding(.vertical,12)
                        } else {
                            ForEach(Array(answer.replies.enumerated()),id:\.offset){ idx,reply in
                                HStack(alignment:.top,spacing:10){
                                    Text("✦").font(.system(size:13)).foregroundColor(accent).frame(width:26,height:26).background(accent.opacity(0.12),in:Circle())
                                    VStack(alignment:.leading,spacing:4){
                                        HStack{
                                            Text(displayAuthor(reply)).font(.system(size:12,weight:.bold)).foregroundColor(Color(hex:0x817276))
                                            Spacer(minLength:0)
                                            if let rid=reply.id, !isOwnReportTarget("reply",rid,in:discussionStory) { Button {openReport("reply",rid)} label:{Text("⚑").font(.system(size:10)).foregroundColor(Color(hex:0xb0a29d)).frame(width:24,height:20)}.buttonStyle(.plain) }
                                        }
                                        answerText(reply.text,side:NativeCamp(rawValue:answer.side))
                                    }
                                    Spacer(minLength:0)
                                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(replyCardSurface,in:RoundedRectangle(cornerRadius:16)).overlay(RoundedRectangle(cornerRadius:16).strokeBorder(replyCardBorder,lineWidth:1))
                                    .transition(.move(edge:.bottom).combined(with:.opacity))
                                    .animation(reduceMotion || !motionOn ? nil:.easeOut(duration:0.3).delay(Double(min(idx,6))*0.04),value:answer.replies.count)
                            }
                        }
                    }.padding(.horizontal,18).padding(.bottom,20)
                }
                HStack(spacing:9){
                    MusicComposer(text:$replyText,height:$replyHeight,focused:$replyFocused,
                                  draft:$replyMusic,camp:side,chinese:zh,prompt:l("写下回复…","Write a reply…"),
                                  maxHeight:104,submit:{appendReply(answer)})
                    Button {appendReply(answer)} label:{
                        Image(systemName:"arrow.up").font(.system(size:16,weight:.semibold))
                            .foregroundColor(.white).frame(width:44,height:44)
                            .background(accent,in:Circle())
                    }.buttonStyle(PressScale()).accessibilityLabel(l("发送回复","Send reply"))
                }.padding(.horizontal,18).padding(.top,8).padding(.bottom,14)
            }
            .frame(width:dialogWidth,height:dialogH)
            .background {
                RoundedRectangle(cornerRadius:20).fill(surface)
            }
            .clipShape(RoundedRectangle(cornerRadius:20))
            .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(accent.opacity(0.22),lineWidth:1))
            .shadow(color:Color(hex:0x45313a).opacity(0.12),radius:12,y:5)
            .position(x:width/2,y:dialogCenter)
        }.frame(width:width,height:height).id(answer.id)
            .transition(fromLibrary ? .move(edge:.trailing) : replyReveal(
                from:replyOrigin,
                to:CGRect(x:(width-dialogWidth)/2,y:dialogCenter-dialogH/2,width:dialogWidth,height:dialogH)
            ))
    }
}

private struct ReportFeedbackSection: View {
    let model: NativeFeedModel
    let viewer: String
    let chinese: Bool
    @State private var feedback: [NativeFeedModel.ReportFeedback] = []
    @State private var failed = false

    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            if failed {
                Button(chinese ? "举报结果加载失败，重试" : "Could not load results. Retry") {
                    Task { await load() }
                }
            }
            ForEach(feedback) { item in
                VStack(alignment:.leading,spacing:4) {
                    Text(item.outcome == "expired" ? (chinese ? "内容已到期" : "Content expired") :
                         (chinese ? "审核已处理" : "Review completed"))
                    if !item.message.isEmpty { Text(item.message).font(.footnote) }
                }
            }
        }.task { await load() }
    }

    @MainActor private func load() async {
        do {
            feedback = try await model.fetchReportFeedback(viewer:viewer)
            failed = false
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

private func replyReveal(from source: CGRect?, to target: CGRect) -> AnyTransition {
    guard let source, !source.isEmpty else { return .opacity }
    return .modifier(
        active:ReplyCardReveal(progress:0,source:source,target:target),
        identity:ReplyCardReveal(progress:1,source:source,target:target)
    )
}

private struct ReplyCardReveal: AnimatableModifier {
    var progress: CGFloat
    let source: CGRect
    let target: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let start = 1-progress
        let width = source.width*start+target.width*progress
        let height = source.height*start+target.height*progress
        let x = source.minX*start+target.minX*progress
        let y = source.minY*start+target.minY*progress
        let shape = RoundedRectangle(cornerRadius:18+2*progress)
        return ZStack(alignment:.topLeading) {
            shape.fill(replyCardSurface)
                .frame(width:width,height:height).offset(x:x,y:y)
                .opacity(Double(start))
            content.opacity(Double(progress))
        }
        .mask(alignment:.topLeading) {
            shape.frame(width:width,height:height).offset(x:x,y:y)
        }
    }
}

func fullCardReveal(from card: CGRect?,width: CGFloat,height: CGFloat,radius: CGFloat) -> AnyTransition {
    guard let card, !card.isEmpty else { return .opacity }
    let size = CGSize(width:width,height:height)
    return .modifier(
        active:StoryContentReveal(progress:0,card:card,size:size,radius:radius),
        identity:StoryContentReveal(progress:1,card:card,size:size,radius:radius)
    )
}

private struct StoryContentReveal: AnimatableModifier {
    var progress: CGFloat
    let card: CGRect
    let size: CGSize
    let radius: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let remaining = 1-progress
        let width = card.width*remaining+size.width*progress
        let height = card.height*remaining+size.height*progress
        let rect = RoundedRectangle(cornerRadius:radius*remaining)
        let x = card.minX*remaining
        let y = card.minY*remaining
        return content
            .environment(\.detailRevealProgress,Double(progress))
            .mask(alignment:.topLeading) {
                rect.frame(width:width,height:height).offset(x:x,y:y)
            }
    }
}

private struct DetailRevealProgress: EnvironmentKey {
    static let defaultValue: Double = 1
}

private extension EnvironmentValues {
    var detailRevealProgress: Double {
        get { self[DetailRevealProgress.self] }
        set { self[DetailRevealProgress.self] = newValue }
    }
}

private struct ConversationForeground: AnimatableModifier {
    var progress: CGFloat
    let incoming: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let visibility = incoming ? (progress-0.48)/0.52 : 1-progress/0.48
        return content.opacity(Double(max(0,min(1,visibility))))
    }
}

private struct DetailAddition: ViewModifier {
    @Environment(\.detailRevealProgress) private var progress

    func body(content: Content) -> some View {
        content
            .offset(y:CGFloat(1-progress)*32)
            .opacity(max(0,min(1,(progress-0.40)/0.60)))
    }
}

private struct MusicCardLabel: View {
    let title: String
    let subtitle: String?
    let accent: Color
    let showArrow: Bool

    var body: some View {
        HStack(spacing:9) {
            Image(systemName:"music.note").font(.system(size:14,weight:.semibold))
                .foregroundColor(accent).frame(width:29,height:29)
                .background(accent.opacity(0.14),in:RoundedRectangle(cornerRadius:8))
                .accessibilityHidden(true)
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(.system(size:13,weight:.semibold)).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.system(size:11)).foregroundColor(H5Design.muted).lineLimit(2)
                }
            }
            Spacer(minLength:5)
            if showArrow {
                Image(systemName:"arrow.up.right").font(.system(size:11,weight:.semibold))
                    .foregroundColor(accent).accessibilityHidden(true)
            }
        }.padding(8).foregroundColor(H5Design.ink)
            .background(accent.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(accent.opacity(0.2),lineWidth:1))
    }
}

private struct MusicComposer: View {
    @Binding var text: String
    @Binding var height: CGFloat
    @Binding var focused: Bool
    @Binding var draft: MusicDraft?
    let camp: NativeCamp?
    let chinese: Bool
    let prompt: String
    var maxHeight: CGFloat = 112
    var submit: (() -> Void)?
    @State private var editing = false
    @State private var replacing = false
    @State private var tooMany = false
    @State private var replacement: MusicDraft?

    private var accent: Color { camp?.accent ?? H5Design.muted }
    private func l(_ zh: String,_ en: String) -> String { chinese ? zh : en }

    var body: some View {
        VStack(spacing:0) {
            if let current = draft {
                HStack(spacing:0) {
                    Button {
                        editing = true
                    } label: {
                        MusicCardLabel(title:current.showTitle && !current.title.isEmpty ? current.title : current.platform,
                                       subtitle:current.showTitle && !current.artist.isEmpty ? current.artist : nil,
                                       accent:accent,showArrow:false)
                    }.buttonStyle(.plain)
                    Button {
                        draft = nil
                    } label: {
                        Image(systemName:"xmark").font(.system(size:12,weight:.semibold))
                            .foregroundColor(H5Design.muted).frame(width:36,height:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(l("移除歌曲","Remove track"))
                }.padding(.leading,6).padding(.top,6)
            }
            GrowField(text:$text,height:$height,focused:$focused,maxHeight:maxHeight,prompt:prompt,
                      returnKey:submit == nil ? .default : .send,submit:submit,pasteTransform:handlePaste)
                .frame(height:height)
        }.background(Color(hex:0xf7f4f1),in:RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(Color(hex:0xeee8e4),lineWidth:1).allowsHitTesting(false))
            .sheet(isPresented:$editing) {
                NavigationView {
                    Form {
                        Toggle(l("显示歌名和歌手","Show title and artist"),isOn:option(\.showTitle,default:false))
                        if draft?.showTitle == true {
                            TextField(l("歌曲名","Track title"),text:option(\.title,default:""))
                            TextField(l("歌手（选填）","Artist (optional)"),text:option(\.artist,default:""))
                        }
                    }.navigationTitle(l("音乐附件","Music attachment")).navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement:.confirmationAction) { Button(l("完成","Done")) { editing = false } } }
                }.navigationViewStyle(.stack)
            }
            .confirmationDialog(l("替换当前歌曲？","Replace the attached track?"),isPresented:$replacing,titleVisibility:.visible) {
                Button(l("替换","Replace")) {
                    if let replacement { attach(replacement) }
                    replacement = nil
                }
                Button(l("取消","Cancel"),role:.cancel) { replacement = nil }
            }
            .alert(l("每条评论或回复只能分享一首歌","Share one track per comment or reply"),isPresented:$tooMany) {
                Button(l("好","OK"),role:.cancel) {}
            }
            .task(id:draft?.id) {
                guard let source = draft, source.title.isEmpty,
                      let result = await source.lookup(), !Task.isCancelled,
                      let title = result.title, !MusicDraft.clean(title).isEmpty,
                      var current = draft, current == source else { return }
                current.title = MusicDraft.clean(title)
                current.artist = MusicDraft.clean(result.artist ?? "")
                current.showTitle = true
                draft = current
            }
    }

    private func option<Value>(_ key: WritableKeyPath<MusicDraft,Value>,default value: Value) -> Binding<Value> {
        Binding(get:{ draft?[keyPath:key] ?? value },set:{ draft?[keyPath:key] = $0 })
    }

    private func attach(_ value: MusicDraft) { draft = value }

    private func handlePaste(_ clipboard: String) -> String? {
        let links = SharedMusicLink.links(in:clipboard)
        guard let first = links.first else { return nil }
        guard links.count == 1 else { tooMany = true; return "" }
        let (incoming,body) = MusicDraft.pasted(clipboard,link:first)
        if let draft, draft.url != incoming.url {
            replacement = incoming
            replacing = true
        } else if draft == nil {
            attach(incoming)
        }
        return body
    }
}

struct GrowField:UIViewRepresentable {
    @Binding var text:String
    @Binding var height:CGFloat
    @Binding var focused:Bool
    var maxHeight:CGFloat = 112
    var label: String?
    var prompt: String?
    var returnKey: UIReturnKeyType = .default
    var submit: (() -> Void)?
    var pasteTransform: ((String) -> String?)?
    func makeUIView(context:Context)->PromptTextView {
        let v=PromptTextView(frame:.zero,textContainer:nil)
        v.backgroundColor = .clear
        v.font = .systemFont(ofSize:16)
        v.textColor = UIColor(red:0.19,green:0.16,blue:0.19,alpha:1)
        v.tintColor = UIColor(red:0.57,green:0.30,blue:0.31,alpha:1)
        v.prompt = prompt
        v.pasteTransform = pasteTransform
        v.returnKeyType = returnKey
        v.textContainerInset = UIEdgeInsets(top:13,left:8,bottom:13,right:8)
        v.textContainer.lineFragmentPadding = 4
        v.isScrollEnabled = false
        v.delegate = context.coordinator
        v.text = text
        v.accessibilityLabel = label ?? prompt
        v.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        return v
    }
    func updateUIView(_ v:PromptTextView,context:Context){
        context.coordinator.parent = self
        v.accessibilityLabel = label ?? prompt
        v.prompt = prompt
        v.pasteTransform = pasteTransform
        if v.markedTextRange == nil && v.text != text { v.text = text }
        if focused && !v.isFirstResponder { v.becomeFirstResponder() }
        if !focused && v.isFirstResponder { v.resignFirstResponder() }
        v.updatePromptVisibility()
        measure(v)
    }
    static func dismantleUIView(_ view: PromptTextView, coordinator: Coordinator) {
        view.delegate = nil
    }
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func measure(_ v:UITextView){
        let w = v.bounds.width
        guard w > 10 else { return }
        let measured = ceil(v.sizeThatFits(CGSize(width:w,height:10000)).height)
        let h = min(maxHeight,max(46,measured))
        v.isScrollEnabled = measured > maxHeight
        if abs(h-height) > 0.5 { DispatchQueue.main.async { height = h } }
    }
    final class Coordinator:NSObject,UITextViewDelegate {
        var parent:GrowField
        init(_ p:GrowField){parent=p}
        func textView(_ tv:UITextView,shouldChangeTextIn range:NSRange,replacementText text:String)->Bool {
            guard text == "\n", tv.markedTextRange == nil, let submit = parent.submit else { return true }
            submit()
            return false
        }
        func textViewDidChange(_ tv:UITextView){
            (tv as? PromptTextView)?.updatePromptVisibility()
            parent.text=tv.text
            parent.measure(tv)
        }
        func textViewDidBeginEditing(_ tv:UITextView){parent.focused=true}
        func textViewDidEndEditing(_ tv:UITextView){parent.focused=false}
    }
}
final class PromptTextView: UITextView {
    private let promptLabel = UILabel()
    var pasteTransform: ((String) -> String?)?

    override func paste(_ sender: Any?) {
        if markedTextRange == nil, let pasteTransform, let clipboard = UIPasteboard.general.string,
           let replacement = pasteTransform(clipboard) {
            if !replacement.isEmpty { insertText(replacement) }
            return
        }
        super.paste(sender)
    }
    var prompt: String? {
        didSet {
            guard oldValue != prompt else { return }
            promptLabel.text = prompt
            updatePromptVisibility()
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame:frame,textContainer:textContainer)
        promptLabel.numberOfLines = 0
        promptLabel.textColor = UIColor(red:0.47,green:0.40,blue:0.41,alpha:1)
        promptLabel.isUserInteractionEnabled = false
        promptLabel.isAccessibilityElement = false
        addSubview(promptLabel)
    }

    required init?(coder: NSCoder) { super.init(coder:coder) }

    func updatePromptVisibility() {
        promptLabel.isHidden = !(text ?? "").isEmpty || prompt?.isEmpty != false
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !promptLabel.isHidden else { return }
        promptLabel.font = font
        let caret = caretRect(for:beginningOfDocument)
        let inset = textContainerInset
        let x = inset.left+textContainer.lineFragmentPadding
        let width = max(1,bounds.width-x-inset.right-textContainer.lineFragmentPadding)
        let size = promptLabel.sizeThatFits(CGSize(width:width,height:CGFloat.greatestFiniteMagnitude))
        promptLabel.frame = CGRect(x:x,y:caret.isEmpty ? inset.top : caret.minY,width:width,height:size.height)
    }
}
private struct TopRoundedShape:Shape {
    let radius:CGFloat
    func path(in r:CGRect)->Path {
        var p=Path()
        p.move(to:CGPoint(x:0,y:r.height))
        p.addLine(to:CGPoint(x:0,y:radius))
        p.addQuadCurve(to:CGPoint(x:radius,y:0),control:CGPoint(x:0,y:0))
        p.addLine(to:CGPoint(x:r.width-radius,y:0))
        p.addQuadCurve(to:CGPoint(x:r.width,y:radius),control:CGPoint(x:r.width,y:0))
        p.addLine(to:CGPoint(x:r.width,y:r.height))
        p.closeSubpath()
        return p
    }
}
