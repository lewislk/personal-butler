package dto

// 与 iOS 端 Data/Mapper/SyncPayload.swift 完全对齐。
// JSON tag 与 Swift Codable 默认策略（属性名原样）保持一致。

// SyncMeta 同步包元信息。v6 起移除 deviceId 字段（单用户单设备，
// 不再需要设备隔离）。dataVersion 当前为 6。
type SyncMeta struct {
	SyncTimestamp int64  `json:"syncTimestamp"`
	AppVersion    string `json:"appVersion"`
	DataVersion   int    `json:"dataVersion"`
}

type SyncTodoDTO struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Source    string   `json:"source"`
	DueDate   *float64 `json:"dueDate"`
	IsDone    bool     `json:"isDone"`
	CreatedAt float64  `json:"createdAt"`
	// v4 新增字段（与 iOS 端 Optional 对齐：指针类型，nil → JSON null）
	TaskType            *string  `json:"taskType,omitempty"`
	RecipeID            *string  `json:"recipeId,omitempty"`
	ExpectedIngredients []string `json:"expectedIngredients,omitempty"`
	CheckedIngredients  []string `json:"checkedIngredients,omitempty"`
}

type SyncScheduleDTO struct {
	ID                    string   `json:"id"`
	Title                 string   `json:"title"`
	Remark                string   `json:"remark"`
	StartDate             float64  `json:"startDate"`
	EndDate               *float64 `json:"endDate"`
	IsAllDay              bool     `json:"isAllDay"`
	ReminderMinutesBefore *int     `json:"reminderMinutesBefore"`
	ColorTag              string   `json:"colorTag"`
	IsCompleted           bool     `json:"isCompleted"`
	// v5 新增：标记首启 Demo 数据；客户端「清理Demo数据」按钮按此过滤。
	// 用 *bool 指针对齐 iOS Optional，旧客户端上传不带此字段时为 nil。
	IsDemo *bool `json:"isDemo,omitempty"`
}

type SyncAnniDTO struct {
	ID                 string  `json:"id"`
	Name               string  `json:"name"`
	Date               float64 `json:"date"`
	IsLunar            bool    `json:"isLunar"`
	Type               string  `json:"type"`
	ReminderDaysBefore *int    `json:"reminderDaysBefore"`
	Emoji              string  `json:"emoji"`
	// v5 新增
	IsDemo *bool `json:"isDemo,omitempty"`
}

type SyncPasswordDTO struct {
	ID            string  `json:"id"`
	Platform      string  `json:"platform"`
	Account       string  `json:"account"`
	TypeText      string  `json:"typeText"`
	Category      string  `json:"category"`
	PasswordPlain string  `json:"passwordPlain"`
	UpdatedAt     float64 `json:"updatedAt"`
	// v5 新增
	IsDemo *bool `json:"isDemo,omitempty"`
}

type SyncOTPDTO struct {
	ID          string `json:"id"`
	Issuer      string `json:"issuer"`
	AccountName string `json:"accountName"`
	SecretPlain string `json:"secretPlain"`
	Period      int    `json:"period"`
	Digits      int    `json:"digits"`
	Order       int    `json:"order"`
	// v5 新增
	IsDemo *bool `json:"isDemo,omitempty"`
}

type SyncFoodDTO struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	Emoji    string   `json:"emoji"`
	Rating   float64  `json:"rating"` // v3：Int→Double（半星评分）
	Tags     []string `json:"tags"`
	Remark   string   `json:"remark"`
	Date     float64  `json:"date"`
	Category string   `json:"category"`
	// v2 位置字段
	PlaceName *string `json:"placeName,omitempty"`
	Address   *string `json:"address,omitempty"`
	Latitude  *float64 `json:"latitude,omitempty"`
	Longitude *float64 `json:"longitude,omitempty"`
	// v3 图片图标（base64 编码的 JPEG bytes；nil = 未设置）
	IconImageBase64 *string `json:"iconImageBase64,omitempty"`
	// v5 新增
	IsDemo *bool `json:"isDemo,omitempty"`
}

// SyncIngredientDTO v4 新增：菜谱结构化食材子项
type SyncIngredientDTO struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Amount string `json:"amount"`
	Order  int    `json:"order"`
}

// SyncCartDTO v4 新增：烹饪车项
type SyncCartDTO struct {
	ID       string  `json:"id"`
	RecipeID string  `json:"recipeId"`
	Servings int     `json:"servings"`
	AddedAt  float64 `json:"addedAt"`
}

type SyncRecipeDTO struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Emoji       string `json:"emoji"`
	Difficulty  string `json:"difficulty"`
	Minutes     int    `json:"minutes"`
	Category    string `json:"category"`
	// v4：原 ingredients 字段类型由 String 改为 [SyncIngredientDTO]
	IngredientsLegacyRaw string                `json:"ingredientsLegacyRaw"`
	Ingredients          []SyncIngredientDTO   `json:"ingredients"`
	Steps                string                `json:"steps"`
	Tips                 string                `json:"tips"`
	// v4 新增：菜谱图片图标（base64 编码的 JPEG bytes）
	IconImageBase64 *string `json:"iconImageBase64,omitempty"`
	// v5 新增
	IsDemo *bool `json:"isDemo,omitempty"`
}

type SyncNoteDTO struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Content   string  `json:"content"`
	Tag       string  `json:"tag"`
	CreatedAt float64 `json:"createdAt"`
	UpdatedAt float64 `json:"updatedAt"`
	// v5 新增
	IsDemo *bool `json:"isDemo,omitempty"`
}

type SyncModuleDTO struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Tag            string `json:"tag"`
	IconSystemName string `json:"iconSystemName"`
	Order          int    `json:"order"`
	ComingSoon     bool   `json:"comingSoon"`
}

type SyncData struct {
	TodoList        []SyncTodoDTO     `json:"todoList"`
	ScheduleList    []SyncScheduleDTO `json:"scheduleList"`
	AnniversaryList []SyncAnniDTO     `json:"anniversaryList"`
	PasswordList    []SyncPasswordDTO `json:"passwordList"`
	OTPList         []SyncOTPDTO      `json:"otpList"`
	FoodRecordList  []SyncFoodDTO     `json:"foodRecordList"`
	CookRecipeList  []SyncRecipeDTO   `json:"cookRecipeList"`
	// v4 新增（与 iOS 端 Optional 对齐：nil → JSON null，旧服务端兼容）
	CartList      []SyncCartDTO   `json:"cartList"`
	NoteList      []SyncNoteDTO   `json:"noteList"`
	AppModuleList []SyncModuleDTO `json:"appModuleList"`
	Setting       map[string]string `json:"setting"`
}

type SyncPayload struct {
	SyncMeta SyncMeta `json:"syncMeta"`
	Data     SyncData `json:"data"`
}

// SyncInfo GET /sync/info 返回体。
// v6 起移除 deviceId 字段。
type SyncInfo struct {
	SyncTimestamp int64  `json:"syncTimestamp"`
	AppVersion    string `json:"appVersion"`
	DataVersion   int    `json:"dataVersion"`
	// TotalCount 备份的实体条数总和（不含 setting）。
	TotalCount int64 `json:"totalCount"`
}

// APIResponse 统一返回结构。
type APIResponse struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data any    `json:"data,omitempty"`
}
