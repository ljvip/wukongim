<script setup lang="ts">
import { nextTick, onMounted, onUnmounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import APIClient from '../services/APIClient'
import Conversation from '../components/Conversation/index.vue'
import MessageUI from '../messages/Message.vue'
import {
  WKSDK, Message, MessageText, Channel, ChannelTypePerson, ChannelTypeGroup,
  MessageStatus, PullMode, MessageContent, ConnectionInfo
} from 'wukongimjssdk'
import { ConnectStatus, ConnectStatusListener, MessageListener, MessageStatusListener, SendackPacket, Setting } from 'wukongimjssdk'

const router = useRouter()
const uid = (router.currentRoute.value.query.uid as string) || ''
const token = (router.currentRoute.value.query.token as string) || 'token111'
const chatRef = ref<HTMLElement | null>(null)
const text = ref('')
const title = ref('微信聊天')
const online = ref(false)
const showConversation = ref(true)
const showTargetPanel = ref(false)
const targetId = ref('')
const targetType = ref<'person' | 'group'>('person')
const loading = ref(false)
const messages = ref<Message[]>([])
const to = ref(new Channel('', 0))
const composing = ref(false)

let connectListener!: ConnectStatusListener
let messageListener!: MessageListener
let statusListener!: MessageStatusListener

const scrollBottom = () => nextTick(() => {
  if (chatRef.value) chatRef.value.scrollTop = chatRef.value.scrollHeight
})

const loadMessages = async () => {
  if (!to.value.channelID) return
  loading.value = true
  try {
    const result = await WKSDK.shared().chatManager.syncMessages(to.value, {
      limit: 30, startMessageSeq: 0, endMessageSeq: 0, pullMode: PullMode.Up
    })
    messages.value = result || []
    scrollBottom()
  } finally {
    loading.value = false
  }
}

const connectIM = (addr: string) => {
  const config = WKSDK.shared().config
  config.uid = uid
  config.token = token
  config.addr = addr
  config.sendCountOfEach = 100000
  WKSDK.shared().config = config

  connectListener = (status: ConnectStatus, _reason?: number, info?: ConnectionInfo) => {
    online.value = status === ConnectStatus.Connected
    title.value = online.value
      ? `${uid} · ${info?.nodeId ? `节点 ${info.nodeId}` : '在线'}`
      : `${uid} · 未连接`
  }
  messageListener = (message: Message) => {
    if (to.value.channelID && to.value.isEqual(message.channel)) {
      messages.value = [...messages.value, message]
      scrollBottom()
    }
  }
  statusListener = (ack: SendackPacket) => {
    const item = messages.value.find(message => message.clientSeq === ack.clientSeq)
    if (item) item.status = ack.reasonCode === 1 ? MessageStatus.Normal : MessageStatus.Fail
  }

  WKSDK.shared().connectManager.addConnectStatusListener(connectListener)
  WKSDK.shared().chatManager.addMessageListener(messageListener)
  WKSDK.shared().chatManager.addMessageStatusListener(statusListener)
  WKSDK.shared().connect()
}

onMounted(async () => {
  if (!APIClient.shared.config.apiURL) {
    router.push('/')
    return
  }
  try {
    const route = await APIClient.shared.get('/route', { param: { uid } })
    connectIM(route.wss_addr || route.ws_addr)
  } catch (error) {
    console.error('连接 IM 失败', error)
  }
})

onUnmounted(() => {
  WKSDK.shared().connectManager.removeConnectStatusListener(connectListener)
  WKSDK.shared().chatManager.removeMessageListener(messageListener)
  WKSDK.shared().chatManager.removeMessageStatusListener(statusListener)
  WKSDK.shared().disconnect()
})

const onSelectChannel = (channel: Channel) => {
  to.value = channel
  messages.value = []
  showConversation.value = false
  loadMessages()
}

const openTarget = () => {
  targetId.value = ''
  showTargetPanel.value = true
}

const confirmTarget = () => {
  if (!targetId.value.trim()) return
  const type = targetType.value === 'person' ? ChannelTypePerson : ChannelTypeGroup
  to.value = new Channel(targetId.value.trim(), type)
  messages.value = []
  showTargetPanel.value = false
  showConversation.value = false
  loadMessages()
  if (type === ChannelTypeGroup) {
    APIClient.shared.joinChannel(to.value.channelID, to.value.channelType, uid).catch(console.error)
  }
}

const send = () => {
  const value = text.value.trim()
  if (!value || !to.value.channelID || !online.value) return
  const content: MessageContent = new MessageText(value)
  WKSDK.shared().chatManager.send(content, to.value, Setting.fromUint8(0))
  text.value = ''
  scrollBottom()
}

const onEnter = (event: KeyboardEvent) => {
  if (composing.value || event.shiftKey) return
  event.preventDefault()
  send()
}

const logout = () => {
  WKSDK.shared().disconnect()
  router.push('/')
}
</script>

<template>
  <main class="wechat-shell">
    <aside class="app-rail">
      <div class="user-avatar">{{ uid.slice(0, 1).toUpperCase() || 'U' }}</div>
      <nav class="rail-nav" aria-label="主导航">
        <button class="rail-button active" title="聊天" @click="showConversation = true">💬</button>
        <button class="rail-button" title="通讯录" @click="openTarget">👥</button>
        <button class="rail-button" title="收藏">☆</button>
      </nav>
      <button class="rail-button rail-bottom" title="退出" @click="logout">↪</button>
    </aside>

    <section class="conversation-panel" :class="{ 'is-open': showConversation }">
      <header class="conversation-header">
        <div>
          <strong>微信聊天</strong>
          <small>{{ online ? '已连接' : '连接中…' }}</small>
        </div>
        <button class="icon-button" title="发起会话" @click="openTarget">＋</button>
      </header>
      <label class="search-box"><span>⌕</span><input placeholder="搜索" /></label>
      <Conversation :onSelectChannel="onSelectChannel" />
    </section>

    <section class="chat-panel" :class="{ 'is-open': !showConversation }">
      <header class="chat-header">
        <button class="back-button" @click="showConversation = true">‹</button>
        <div class="chat-title">
          <strong>{{ to.channelID ? to.channelID : '选择一个聊天' }}</strong>
          <small v-if="to.channelID">{{ to.channelType === ChannelTypeGroup ? '群聊' : '单聊' }}</small>
        </div>
        <button class="icon-button" title="更多" @click="openTarget">···</button>
      </header>

      <div ref="chatRef" class="message-list">
        <div v-if="loading" class="empty-state">正在加载消息…</div>
        <div v-else-if="!to.channelID" class="empty-state"><span>💬</span><p>选择会话开始聊天</p></div>
        <div v-else-if="messages.length === 0" class="empty-state"><span>🌱</span><p>还没有消息，发一条吧</p></div>
        <template v-else>
          <div v-for="message in messages" :id="message.clientMsgNo" :key="message.clientMsgNo" class="message-row" :class="{ mine: message.send }">
            <img class="message-avatar" :src="`https://api.dicebear.com/9.x/initials/svg?seed=${message.fromUID || 'user'}`" alt="头像" />
            <div class="message-content">
              <span v-if="!message.send" class="sender-name">{{ message.fromUID }}</span>
              <div class="bubble"><MessageUI :message="message" /></div>
              <span v-if="message.status === MessageStatus.Fail" class="send-error">发送失败</span>
            </div>
          </div>
        </template>
      </div>

      <footer class="composer">
        <div class="composer-tools"><button title="表情">☺</button><button title="图片">▧</button><button title="文件">⌕</button></div>
        <textarea v-model="text" placeholder="输入消息，Enter 发送" rows="1" @keydown.enter="onEnter" @compositionstart="composing = true" @compositionend="composing = false" />
        <button class="send-button" :disabled="!text.trim() || !to.channelID || !online" @click="send">发送</button>
      </footer>
    </section>

    <div v-if="showTargetPanel" class="modal-backdrop" @click.self="showTargetPanel = false">
      <div class="target-modal">
        <h3>发起聊天</h3>
        <div class="target-tabs"><button :class="{ selected: targetType === 'person' }" @click="targetType = 'person'">个人</button><button :class="{ selected: targetType === 'group' }" @click="targetType = 'group'">群聊</button></div>
        <input v-model="targetId" autofocus :placeholder="targetType === 'person' ? '输入对方 UID' : '输入群组 ID'" @keyup.enter="confirmTarget" />
        <div class="modal-actions"><button @click="showTargetPanel = false">取消</button><button class="primary" @click="confirmTarget">开始聊天</button></div>
      </div>
    </div>
  </main>
</template>
