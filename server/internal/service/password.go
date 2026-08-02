package service

import (
	"errors"
	"time"

	"github.com/lewis/personal-butler/internal/dto"
	"github.com/lewis/personal-butler/internal/model"
	"gorm.io/gorm"
)

// PasswordService 提供 Web 表单录入密码所需的 CRUD 能力。
//
// v6 起移除 device_id 维度，所有数据全局共享（单用户单设备场景）。
// 模式与 RecipeService 一致：单条增删改，每次写入后 upsert sync_meta。
type PasswordService struct {
	db *gorm.DB
}

func NewPasswordService(db *gorm.DB) *PasswordService { return &PasswordService{db: db} }

var (
	ErrPasswordNotFound   = errors.New("password not found")
	ErrPasswordIDMismatch = errors.New("password id in path does not match body")
)

// PasswordInput 与 Web 表单提交结构对齐。
// ID POST 时留空（服务端生成 UUID）；PUT 时必填且与 path 一致。
// Category 留空时后端兜底为 "social"（与 iOS PasswordCategory 默认值一致）。
type PasswordInput struct {
	ID            *string `json:"id,omitempty"`
	Platform      string  `json:"platform"`
	Account       string  `json:"account"`
	PasswordPlain string  `json:"passwordPlain"`
	TypeText      string  `json:"typeText"`
	Category      string  `json:"category"`
}

// List 返回所有密码，按 updatedAt 倒序（与 iOS PasswordView 排序一致）。
func (s *PasswordService) List() ([]dto.SyncPasswordDTO, error) {
	var rows []model.Password
	if err := s.db.Order("updated_at desc").Find(&rows).Error; err != nil {
		return nil, err
	}
	out := make([]dto.SyncPasswordDTO, 0, len(rows))
	for _, p := range rows {
		out = append(out, dto.SyncPasswordDTO{
			ID:            p.ID,
			Platform:      p.Platform,
			Account:       p.Account,
			TypeText:      p.TypeText,
			Category:      p.Category,
			PasswordPlain: p.PasswordPlain,
			UpdatedAt:     p.UpdatedAt,
			IsDemo:        boolPtr(p.IsDemo),
		})
	}
	return out, nil
}

// Get 取单个密码。
func (s *PasswordService) Get(id string) (*dto.SyncPasswordDTO, error) {
	var p model.Password
	if err := s.db.Where("id = ?", id).First(&p).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrPasswordNotFound
		}
		return nil, err
	}
	return &dto.SyncPasswordDTO{
		ID:            p.ID,
		Platform:      p.Platform,
		Account:       p.Account,
		TypeText:      p.TypeText,
		Category:      p.Category,
		PasswordPlain: p.PasswordPlain,
		UpdatedAt:     p.UpdatedAt,
		IsDemo:        boolPtr(p.IsDemo),
	}, nil
}

// Create 新建密码。返回新 id。
func (s *PasswordService) Create(in *PasswordInput) (string, error) {
	id := newUUID()
	category := in.Category
	if category == "" {
		category = "social"
	}
	p := model.Password{
		ID:            id,
		Platform:      in.Platform,
		Account:       in.Account,
		TypeText:      in.TypeText,
		Category:      category,
		PasswordPlain: in.PasswordPlain,
		UpdatedAt:     float64(time.Now().Unix()),
	}
	err := s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(&p).Error; err != nil {
			return err
		}
		return upsertSyncMeta(tx)
	})
	if err != nil {
		return "", err
	}
	return id, nil
}

// Update 全量更新密码字段。
func (s *PasswordService) Update(id string, in *PasswordInput) error {
	if in.ID == nil || *in.ID != id {
		return ErrPasswordIDMismatch
	}
	var exists model.Password
	if err := s.db.Where("id = ?", id).First(&exists).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrPasswordNotFound
		}
		return err
	}
	category := in.Category
	if category == "" {
		category = "social"
	}
	err := s.db.Transaction(func(tx *gorm.DB) error {
		updates := map[string]any{
			"platform":       in.Platform,
			"account":        in.Account,
			"type_text":      in.TypeText,
			"category":       category,
			"password_plain": in.PasswordPlain,
			"updated_at":     float64(time.Now().Unix()),
		}
		if err := tx.Model(&model.Password{}).
			Where("id = ?", id).
			Updates(updates).Error; err != nil {
			return err
		}
		return upsertSyncMeta(tx)
	})
	return err
}

// Delete 删除密码。
func (s *PasswordService) Delete(id string) error {
	var exists model.Password
	if err := s.db.Where("id = ?", id).First(&exists).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrPasswordNotFound
		}
		return err
	}
	return s.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("id = ?", id).
			Delete(&model.Password{}).Error; err != nil {
			return err
		}
		return upsertSyncMeta(tx)
	})
}
