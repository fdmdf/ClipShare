package top.coclyun.clipshare.adapter

data class History(
    val id: Long,
    val content: String,
    val time: String,
    var top: Boolean,
    val type: String
)