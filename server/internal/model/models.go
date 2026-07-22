package model

import "time"

// 所有业务表都以 (device_id, id) 作为复合主键：
// - device_id：来自请求头 X-Device-ID，用来把多设备数据隔离开
// - id：客户端 SwiftData 里那条实体的 UUID（AppModule 是稳定字符串 id）
//
// 上传采用「按 device_id 清空 → 批量插入」的全量覆盖语义，
// 与客户端「MVP 只支持全量覆盖」的约定一致，也避免了差量合并的复杂度。

// SyncMetaRow 记录每个设备最近一次成功上传的元信息，供 /sync/info 查询。
type SyncMetaRow struct {
	DeviceID      string `gorm:"primaryKey;size:64" json:"deviceId"`
	SyncTimestamp int64  `gorm:"not null" json:"syncTimestamp"`
	AppVersion    string `gorm:"size:32" json:"appVersion"`
	DataVersion   int    `gorm:"not null" json:"dataVersion"`
	UpdatedAt     time.Time
}

func (SyncMetaRow) TableName() string { return "sync_meta" }

type Todo struct {
	DeviceID  string   `gorm:"primaryKey;size:64"`
	ID        string   `gorm:"primaryKey;size:64"`
	Name      string   `gorm:"size:255"`
	Source    string   `gorm:"size:32"`
	DueDate   *float64 `gorm:"type:double"`
	IsDone    bool
	CreatedAt float64 `gorm:"type:double"`
}

func (Todo) TableName() string { return "todo" }

type Schedule struct {
	DeviceID              string `gorm:"primaryKey;size:64"`
	ID                    string `gorm:"primaryKey;size:64"`
	Title                 string `gorm:"size:255"`
	Remark                string `gorm:"type:text"`
	StartDate             float64
	EndDate               *float64
	IsAllDay              bool
	ReminderMinutesBefore *int
	ColorTag              string `gorm:"size:32"`
	IsCompleted           bool
}

func (Schedule) TableName() string { return "schedule" }

type Anniversary struct {
	DeviceID           string `gorm:"primaryKey;size:64"`
	ID                 string `gorm:"primaryKey;size:64"`
	Name               string `gorm:"size:255"`
	Date               float64
	IsLunar            bool
	Type               string `gorm:"size:32"`
	ReminderDaysBefore *int
	Emoji              string `gorm:"size:16"`
}

func (Anniversary) TableName() string { return "anniversary" }

type Password struct {
	DeviceID      string `gorm:"primaryKey;size:64"`
	ID            string `gorm:"primaryKey;size:64"`
	Platform      string `gorm:"size:128"`
	Account       string `gorm:"size:255"`
	TypeText      string `gorm:"size:64"`
	Category      string `gorm:"size:64"`
	PasswordPlain string `gorm:"type:text"`
	UpdatedAt     float64
}

func (Password) TableName() string { return "password" }

type OTP struct {
	DeviceID    string `gorm:"primaryKey;size:64"`
	ID          string `gorm:"primaryKey;size:64"`
	Issuer      string `gorm:"size:128"`
	AccountName string `gorm:"size:255"`
	SecretPlain string `gorm:"type:text"`
	Period      int
	Digits      int
	OrderIdx    int `gorm:"column:order_idx"`
}

func (OTP) TableName() string { return "otp" }

type Food struct {
	DeviceID string `gorm:"primaryKey;size:64"`
	ID       string `gorm:"primaryKey;size:64"`
	Name     string `gorm:"size:255"`
	Emoji    string `gorm:"size:16"`
	Rating   int
	// Tags 存 JSON 数组字符串，如 ["酸","辣"]，读回时序列化回 []string
	Tags     string `gorm:"type:text"`
	Remark   string `gorm:"type:text"`
	Date     float64
	Category string `gorm:"size:64"`
}

func (Food) TableName() string { return "food" }

type Recipe struct {
	DeviceID    string `gorm:"primaryKey;size:64"`
	ID          string `gorm:"primaryKey;size:64"`
	Name        string `gorm:"size:255"`
	Emoji       string `gorm:"size:16"`
	Difficulty  string `gorm:"size:32"`
	Minutes     int
	Category    string `gorm:"size:64"`
	Ingredients string `gorm:"type:text"`
	Steps       string `gorm:"type:text"`
	Tips        string `gorm:"type:text"`
}

func (Recipe) TableName() string { return "cook_recipe" }

type Note struct {
	DeviceID  string `gorm:"primaryKey;size:64"`
	ID        string `gorm:"primaryKey;size:64"`
	Title     string `gorm:"size:255"`
	Content   string `gorm:"type:mediumtext"`
	Tag       string `gorm:"size:64"`
	CreatedAt float64
	UpdatedAt float64
}

func (Note) TableName() string { return "note" }

type AppModule struct {
	DeviceID       string `gorm:"primaryKey;size:64"`
	ID             string `gorm:"primaryKey;size:64"`
	Name           string `gorm:"size:64"`
	Tag            string `gorm:"size:32"`
	IconSystemName string `gorm:"size:64"`
	OrderIdx       int    `gorm:"column:order_idx"`
	ComingSoon     bool
}

func (AppModule) TableName() string { return "app_module" }

type AppSetting struct {
	DeviceID string `gorm:"primaryKey;size:64"`
	Key      string `gorm:"primaryKey;size:64"`
	Value    string `gorm:"type:text"`
}

func (AppSetting) TableName() string { return "app_setting" }
