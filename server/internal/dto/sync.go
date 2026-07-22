package dto

// 与 iOS 端 Data/Mapper/SyncPayload.swift 完全对齐。
// JSON tag 与 Swift Codable 默认策略（属性名原样）保持一致。

type SyncMeta struct {
	DeviceID      string `json:"deviceId"`
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
}

type SyncAnniDTO struct {
	ID                 string  `json:"id"`
	Name               string  `json:"name"`
	Date               float64 `json:"date"`
	IsLunar            bool    `json:"isLunar"`
	Type               string  `json:"type"`
	ReminderDaysBefore *int    `json:"reminderDaysBefore"`
	Emoji              string  `json:"emoji"`
}

type SyncPasswordDTO struct {
	ID            string  `json:"id"`
	Platform      string  `json:"platform"`
	Account       string  `json:"account"`
	TypeText      string  `json:"typeText"`
	Category      string  `json:"category"`
	PasswordPlain string  `json:"passwordPlain"`
	UpdatedAt     float64 `json:"updatedAt"`
}

type SyncOTPDTO struct {
	ID          string `json:"id"`
	Issuer      string `json:"issuer"`
	AccountName string `json:"accountName"`
	SecretPlain string `json:"secretPlain"`
	Period      int    `json:"period"`
	Digits      int    `json:"digits"`
	Order       int    `json:"order"`
}

type SyncFoodDTO struct {
	ID       string   `json:"id"`
	Name     string   `json:"name"`
	Emoji    string   `json:"emoji"`
	Rating   int      `json:"rating"`
	Tags     []string `json:"tags"`
	Remark   string   `json:"remark"`
	Date     float64  `json:"date"`
	Category string   `json:"category"`
}

type SyncRecipeDTO struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Emoji       string `json:"emoji"`
	Difficulty  string `json:"difficulty"`
	Minutes     int    `json:"minutes"`
	Category    string `json:"category"`
	Ingredients string `json:"ingredients"`
	Steps       string `json:"steps"`
	Tips        string `json:"tips"`
}

type SyncNoteDTO struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Content   string  `json:"content"`
	Tag       string  `json:"tag"`
	CreatedAt float64 `json:"createdAt"`
	UpdatedAt float64 `json:"updatedAt"`
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
	NoteList        []SyncNoteDTO     `json:"noteList"`
	AppModuleList   []SyncModuleDTO   `json:"appModuleList"`
	Setting         map[string]string `json:"setting"`
}

type SyncPayload struct {
	SyncMeta SyncMeta `json:"syncMeta"`
	Data     SyncData `json:"data"`
}

// SyncInfo GET /sync/info 返回体。
type SyncInfo struct {
	DeviceID      string `json:"deviceId"`
	SyncTimestamp int64  `json:"syncTimestamp"`
	AppVersion    string `json:"appVersion"`
	DataVersion   int    `json:"dataVersion"`
	// TotalCount 该 device 备份的实体条数总和（不含 setting）。
	TotalCount int64 `json:"totalCount"`
}

// APIResponse 统一返回结构。
type APIResponse struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data any    `json:"data,omitempty"`
}
